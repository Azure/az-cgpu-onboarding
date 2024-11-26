#!/bin/bash
OPENSSL_VER=${1:-"3.3.1"}

sudo apt-get -o DPkg::Lock::Timeout=300 update
sudo apt-get -o DPkg::Lock::Timeout=300 install -y wget tar build-essential
wget "https://www.openssl.org/source/openssl-${OPENSSL_VER}.tar.gz"
tar -zxvf "openssl-${OPENSSL_VER}.tar.gz"

pushd .
cd "openssl-${OPENSSL_VER}"
./Configure --prefix=/opt/openssl --openssldir=/usr/local/ssl
make -j$(nproc)
sudo make install
popd

rm -rf "openssl-${OPENSSL_VER}" "openssl-${OPENSSL_VER}.tar.gz"
