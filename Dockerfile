# syntax=docker/dockerfile:1

FROM ubuntu:22.04

ARG DEBIAN_FRONTEND=noninteractive
ARG TARGETARCH

ENV AGENT_HOME=/home/agent-admin/agent-app \
    AGENT_PORT=15034 \
    AGENT_UPLOAD_DIR=/home/agent-admin/agent-app/upload_files \
    AGENT_KEY_PATH=/home/agent-admin/agent-app/api_keys \
    AGENT_LOG_DIR=/var/log/agent-app \
    AGENT_PROCESS_PATTERN="agent-app|agent_app.py"

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        acl \
        ca-certificates \
        cron \
        findutils \
        gzip \
        iproute2 \
        openssh-server \
        procps \
        sudo \
        ufw \
        unzip \
    && rm -rf /var/lib/apt/lists/*

RUN groupadd --system agent-common \
    && groupadd --system agent-core \
    && useradd --create-home --shell /bin/bash agent-admin \
    && useradd --create-home --shell /bin/bash agent-dev \
    && useradd --create-home --shell /bin/bash agent-test \
    && usermod --append --groups agent-common,agent-core agent-admin \
    && usermod --append --groups agent-common,agent-core agent-dev \
    && usermod --append --groups agent-common agent-test \
    && printf '%s\n' \
        'agent-admin:agentpass' \
        'agent-dev:agentpass' \
        'agent-test:agentpass' \
        | chpasswd

RUN mkdir -p /run/sshd /etc/ssh/sshd_config.d \
    && sed -i 's/^[#[:space:]]*Port[[:space:]].*/# Port is managed by \/etc\/ssh\/sshd_config.d\/agent-lab.conf/' /etc/ssh/sshd_config \
    && sed -i 's/^[#[:space:]]*PermitRootLogin[[:space:]].*/# PermitRootLogin is managed by \/etc\/ssh\/sshd_config.d\/agent-lab.conf/' /etc/ssh/sshd_config \
    && printf '%s\n' \
        'Port 20022' \
        'PermitRootLogin no' \
        'PasswordAuthentication yes' \
        'PubkeyAuthentication yes' \
        > /etc/ssh/sshd_config.d/agent-lab.conf

RUN mkdir -p \
        "${AGENT_HOME}/bin" \
        "${AGENT_UPLOAD_DIR}" \
        "${AGENT_KEY_PATH}" \
        "${AGENT_LOG_DIR}" \
        /var/log/monitor/agent-app/archive \
    && printf 'agent_api_key_test\n' > "${AGENT_KEY_PATH}/t_secret.key" \
    && printf 'agent_api_key_test\n' > "${AGENT_KEY_PATH}/secret.key" \
    && chown -R agent-admin:agent-core "${AGENT_HOME}" \
    && chown agent-admin:agent-common "${AGENT_HOME}" \
    && chown agent-admin:agent-common "${AGENT_UPLOAD_DIR}" \
    && chown -R agent-admin:agent-core "${AGENT_KEY_PATH}" "${AGENT_LOG_DIR}" /var/log/monitor/agent-app \
    && chmod 2710 "${AGENT_HOME}" \
    && chmod 2750 "${AGENT_HOME}/bin" \
    && chmod 2770 "${AGENT_UPLOAD_DIR}" "${AGENT_KEY_PATH}" "${AGENT_LOG_DIR}" /var/log/monitor/agent-app /var/log/monitor/agent-app/archive \
    && chmod 0660 "${AGENT_KEY_PATH}/t_secret.key" "${AGENT_KEY_PATH}/secret.key" \
    && setfacl -m g:agent-common:rwx,d:g:agent-common:rwx,o::---,d:o::--- "${AGENT_UPLOAD_DIR}" \
    && setfacl -m g:agent-core:rwx,d:g:agent-core:rwx,o::---,d:o::--- "${AGENT_KEY_PATH}" "${AGENT_LOG_DIR}" /var/log/monitor/agent-app /var/log/monitor/agent-app/archive \
    && setfacl -m g:agent-core:rw-,o::--- "${AGENT_KEY_PATH}/t_secret.key" "${AGENT_KEY_PATH}/secret.key"

COPY agent-app.zip /tmp/agent-app.zip
RUN mkdir -p /tmp/agent-app \
    && unzip -q /tmp/agent-app.zip -d /tmp/agent-app \
    && case "${TARGETARCH}" in \
        arm64) install -o agent-admin -g agent-core -m 0750 /tmp/agent-app/agent-app-linux-arm64 "${AGENT_HOME}/agent-app" ;; \
        *) install -o agent-admin -g agent-core -m 0750 /tmp/agent-app/agent-app "${AGENT_HOME}/agent-app" ;; \
    esac \
    && rm -rf /tmp/agent-app /tmp/agent-app.zip

COPY bin/monitor.sh /tmp/monitor.sh
COPY bin/report.sh /tmp/report.sh
COPY bin/archive_logs.sh /tmp/archive_logs.sh
RUN install -o agent-dev -g agent-core -m 0750 /tmp/monitor.sh "${AGENT_HOME}/bin/monitor.sh" \
    && install -o agent-dev -g agent-core -m 0750 /tmp/report.sh "${AGENT_HOME}/bin/report.sh" \
    && install -o agent-dev -g agent-core -m 0750 /tmp/archive_logs.sh "${AGENT_HOME}/bin/archive_logs.sh" \
    && rm -f /tmp/monitor.sh /tmp/report.sh /tmp/archive_logs.sh

RUN printf '%s\n' \
        "export AGENT_HOME=${AGENT_HOME}" \
        "export AGENT_PORT=${AGENT_PORT}" \
        "export AGENT_UPLOAD_DIR=${AGENT_UPLOAD_DIR}" \
        "export AGENT_KEY_PATH=${AGENT_KEY_PATH}" \
        "export AGENT_LOG_DIR=${AGENT_LOG_DIR}" \
        "export AGENT_PROCESS_PATTERN=\"${AGENT_PROCESS_PATTERN}\"" \
        > /etc/profile.d/agent-env.sh \
    && chmod 0644 /etc/profile.d/agent-env.sh \
    && printf '%s\n' \
        'SHELL=/bin/bash' \
        'PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin' \
        "AGENT_HOME=${AGENT_HOME}" \
        "AGENT_PORT=${AGENT_PORT}" \
        "AGENT_UPLOAD_DIR=${AGENT_UPLOAD_DIR}" \
        "AGENT_KEY_PATH=${AGENT_KEY_PATH}" \
        "AGENT_LOG_DIR=${AGENT_LOG_DIR}" \
        "AGENT_PROCESS_PATTERN=${AGENT_PROCESS_PATTERN}" \
        "* * * * * ${AGENT_HOME}/bin/monitor.sh >> ${AGENT_LOG_DIR}/monitor.cron.log 2>&1" \
        "20 3 * * * ${AGENT_HOME}/bin/archive_logs.sh >> ${AGENT_LOG_DIR}/archive.cron.log 2>&1" \
        > /tmp/agent-admin-cron \
    && crontab -u agent-admin /tmp/agent-admin-cron \
    && rm -f /tmp/agent-admin-cron

COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod 0755 /usr/local/bin/entrypoint.sh

EXPOSE 20022 15034

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
