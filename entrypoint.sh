#!/bin/bash
set -e

CA_CERTIFICATES_PATH=${CA_CERTIFICATES_PATH:-$GITLAB_CI_MULTI_RUNNER_DATA_DIR/certs/ca.crt}

create_data_dir() {
  mkdir -p ${GITLAB_CI_MULTI_RUNNER_DATA_DIR}
  chown ${GITLAB_CI_MULTI_RUNNER_USER}:${GITLAB_CI_MULTI_RUNNER_USER} ${GITLAB_CI_MULTI_RUNNER_DATA_DIR}
  mkdir -p ${GITLAB_CI_MULTI_RUNNER_DATA_DIR}/tmp/
  chown ${GITLAB_CI_MULTI_RUNNER_USER}:${GITLAB_CI_MULTI_RUNNER_USER} ${GITLAB_CI_MULTI_RUNNER_DATA_DIR}/tmp/
  mkdir -p ${GITLAB_CI_MULTI_RUNNER_DATA_DIR}/.conan/
  chown ${GITLAB_CI_MULTI_RUNNER_USER}:${GITLAB_CI_MULTI_RUNNER_USER} ${GITLAB_CI_MULTI_RUNNER_DATA_DIR}/.conan/
}

generate_ssh_deploy_keys() {
  sudo -HEu ${GITLAB_CI_MULTI_RUNNER_USER} mkdir -p ${GITLAB_CI_MULTI_RUNNER_DATA_DIR}/.ssh/

  if [[ ! -e ${GITLAB_CI_MULTI_RUNNER_DATA_DIR}/.ssh/id_rsa || ! -e ${GITLAB_CI_MULTI_RUNNER_DATA_DIR}/.ssh/id_rsa.pub ]]; then
    echo "Generating SSH deploy keys..."
    rm -rf ${GITLAB_CI_MULTI_RUNNER_DATA_DIR}/.ssh/id_rsa ${GITLAB_CI_MULTI_RUNNER_DATA_DIR}/.ssh/id_rsa.pub
    sudo -HEu ${GITLAB_CI_MULTI_RUNNER_USER} ssh-keygen -t rsa -N "" -f ${GITLAB_CI_MULTI_RUNNER_DATA_DIR}/.ssh/id_rsa

    echo ""
  fi
  echo -n "Your SSH deploy key is: "
  cat ${GITLAB_CI_MULTI_RUNNER_DATA_DIR}/.ssh/id_rsa.pub
  echo ""

  chmod 600 ${GITLAB_CI_MULTI_RUNNER_DATA_DIR}/.ssh/id_rsa ${GITLAB_CI_MULTI_RUNNER_DATA_DIR}/.ssh/id_rsa.pub
  chmod 700 ${GITLAB_CI_MULTI_RUNNER_DATA_DIR}/.ssh
  chown -R ${GITLAB_CI_MULTI_RUNNER_USER}:${GITLAB_CI_MULTI_RUNNER_USER} ${GITLAB_CI_MULTI_RUNNER_DATA_DIR}/.ssh/
}

update_ca_certificates() {
  if [[ -f ${CA_CERTIFICATES_PATH} ]]; then
    echo "Updating CA certificates..."
    cp "${CA_CERTIFICATES_PATH}" /usr/local/share/ca-certificates/ca.crt
    update-ca-certificates --fresh >/dev/null
  fi
}

grant_access_to_docker_socket() {
  if [ -S /run/docker.sock ]; then
    DOCKER_SOCKET_GID=$(stat -c %g  /run/docker.sock)
    DOCKER_SOCKET_GROUP=$(stat -c %G /run/docker.sock)
    if [[ ${DOCKER_SOCKET_GROUP} == "UNKNOWN" ]]; then
      DOCKER_SOCKET_GROUP=docker_host
      groupadd -g ${DOCKER_SOCKET_GID} ${DOCKER_SOCKET_GROUP}
    fi
    usermod -a -G ${DOCKER_SOCKET_GROUP} ${GITLAB_CI_MULTI_RUNNER_USER}
  fi
}

configure_ci_runner() {
  if [[ ! -e ${GITLAB_CI_MULTI_RUNNER_DATA_DIR}/config.toml ]]; then
    if [[ -n ${CI_SERVER_URL} && -n ${RUNNER_TOKEN} && -n ${RUNNER_DESCRIPTION} && -n ${RUNNER_EXECUTOR} && -n ${CI_CLONE_URL} && -n ${RUNNER_NETWORK} ]]; then
      sudo -HEu ${GITLAB_CI_MULTI_RUNNER_USER} \
        gitlab-runner register --config ${GITLAB_CI_MULTI_RUNNER_DATA_DIR}/config.toml \
	-n -u "${CI_SERVER_URL}" --clone-url "${CI_CLONE_URL}" -r "${RUNNER_TOKEN}" --name "${RUNNER_DESCRIPTION}" --docker-hostname "${RUNNER_DESCRIPTION}" --executor "${RUNNER_EXECUTOR}" --docker-image "docker:stable" --docker-volumes /var/run/docker.sock:/var/run/docker.sock --docker-volumes ${RUNNER_BUILD_DIR}/.ssh:/root/.ssh --docker-volumes ${RUNNER_BUILD_DIR}/builds:/builds --docker-volumes ${RUNNER_BUILD_DIR}/.conan:/root/.conan --docker-network-mode "${RUNNER_NETWORK}" --docker-dns ${DNS_IP} --env RUNNER_BUILD_DIR=${RUNNER_BUILD_DIR} --env "CONAN_DOCKER_RUN_OPTIONS=-v ${RUNNER_BUILD_DIR}\$CI_PROJECT_DIR:/home/conan/project -v ${RUNNER_BUILD_DIR}/.ssh:/home/conan/.ssh -v ${RUNNER_BUILD_DIR}/tmp:/tmp -v ${RUNNER_BUILD_DIR}/.conan:/home/conan/.conan --dns=${DNS_IP} --network=${RUNNER_NETWORK}" --env "CONAN_DOCKER_HOME=/home" --env "CONAN_DOCKER_SHELL=/bin/bash -c" --output-limit "20480"
      echo "Running on ${RUNNER_NETWORK}..."
    else
      sudo -HEu ${GITLAB_CI_MULTI_RUNNER_USER} \
        gitlab-runner register --config ${GITLAB_CI_MULTI_RUNNER_DATA_DIR}/config.toml
    fi
  fi
}

# allow arguments to be passed to gitlab-ci-multi-runner
if [[ ${1:0:1} = '-' ]]; then
  EXTRA_ARGS="$@"
  set --
elif [[ ${1} == gitlab-runner || ${1} == $(which gitlab-runner) ]]; then
  EXTRA_ARGS="${@:2}"
  set --
fi

# default behaviour is to launch gitlab-ci-multi-runner
if [[ -z ${1} ]]; then
  create_data_dir
  update_ca_certificates
  generate_ssh_deploy_keys
  grant_access_to_docker_socket
  configure_ci_runner

  start-stop-daemon --start \
    --chuid ${GITLAB_CI_MULTI_RUNNER_USER}:${GITLAB_CI_MULTI_RUNNER_USER} \
    --exec /usr/local/bin/gitlab-runner -- --debug run \
      --working-directory ${GITLAB_CI_MULTI_RUNNER_DATA_DIR} \
      --config ${GITLAB_CI_MULTI_RUNNER_DATA_DIR}/config.toml ${EXTRA_ARGS}
else
  exec "$@"
fi
