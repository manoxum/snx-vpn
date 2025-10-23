
FROM ubuntu:14.04

# Instalação e configuração do VPN
RUN dpkg --add-architecture i386 && apt-get update \
    && apt-get install -y bzip2 libstdc++5:i386 libx11-6:i386 libpam0g:i386 libnss3:i386 libxext6:i386 libxrender1:i386 sudo wget

RUN apt update && apt install -y openssh-server  expect && \
    mkdir /var/run/sshd

COPY app/lib/snx_install_linux30.sh /tmp/
RUN chmod +x /tmp/snx_install_linux30.sh && /tmp/snx_install_linux30.sh



EXPOSE 22

WORKDIR /app

COPY app .

RUN chmod +x bin/*.sh

ENTRYPOINT ["/app/bin/entrypoint.sh"]
CMD ["bash"]
