#!/bin/bash

BOOTSTRAP_HOME="${BOOTSTRAP_HOME:-/root}"

ks_fetch() {
  if [ -n "$KS" ]; then
    mkdir -p "${BOOTSTRAP_HOME}/`dirname "$1"`"
    wget -q -O "${BOOTSTRAP_HOME}/${1}" "$KS/${1}"
  fi
  if [ -n "$2" ]; then
    cp -p "${BOOTSTRAP_HOME}/${1}" "$2"
    return $?
  fi
  test -e "${BOOTSTRAP_HOME}/$1"
  return $?
}

expand() {
  ks_fetch "$1" || return $?
  if [ -e /usr/bin/interp ]; then
    /usr/bin/interp < "${BOOTSTRAP_HOME}/$1" > "$2"
  else
    # perl fallback
    perl -pe 's/\{\{(.*?)\}\}/$ENV{$1}/ge' < "${BOOTSTRAP_HOME}/$1" > "$2"
  fi
}

from_github() {
  local url="$1"
  shift
  local dst="$1"
  shift
  local release="$1"
  shift
  release="${release:-master}"
  local name="${url##*/}"
  mkdir -p "$dst"
  mkdir -p "${BOOTSTRAP_HOME}/sources"
  wget -q -O "${BOOTSTRAP_HOME}/sources/$name-${release}.tar.gz" "$url/archive/${release}.tar.gz"
  tar -zxf "${BOOTSTRAP_HOME}/sources/$name-${release}.tar.gz" -C "$dst" --strip=1 "$@"
  chown -R root:root "$dst"
  chmod -R o-w "$dst"
}

ubuntu_backport_install() {
  local pkg="$1"
  local src="$2"
  local workdir="${TMPDIR:-/tmp}/deb-$pkg"
  apt-get install --no-install-recommends -y \
    debhelper \
    devscripts \
    dh-autoreconf \
    dh-make \
    dh-make-perl \
    dh-python \
    dpkg-dev \
    equivs \
    ubuntu-dev-tools \
    libdistro-info-perl
  env DEBFULLNAME="James Flemer" DEBEMAIL="james.flemer@ndpgroup.com" UBUMAIL="james.flemer@ndpgroup.com" \
    backportpackage --update --dont-sign --workdir="$workdir" ${src:+--source=$src} "$pkg"
  mkdir -p "$workdir/$pkg.build"
  tar -xf "$workdir/$pkg"*.orig.tar* --strip=1 -C "$workdir/$pkg.build"
  tar -xf "$workdir/$pkg"*ubuntu*.tar.gz -C "$workdir/$pkg.build"
  local d
  for d in "$workdir/$pkg.build/debian" "$workdir/$pkg.build"/*/debian; do
    if [ -d "$d" ]; then
      echo "y" | mk-build-deps -i -r "$d/control"
      (cd "$d/.." && dpkg-buildpackage -j`grep -c rocessor /proc/cpuinfo` -b -nc -us -uc)
      dpkg -i "$d"/../../*.deb
      mkdir -p "${BOOTSTRAP_HOME}/sources"
      cp "$d"/../../*.deb "${BOOTSTRAP_HOME}/sources/"
      break
    fi
  done
  rm -rf "$workdir"
}

deploy() {
  export DEBIAN_FRONTEND=noninteractive

  vendor=`lsb_release -si 2>/dev/null`
  if [ -z "$vendor" ]; then
    if [ -e /etc/redhat-release ]; then
      vendor=`awk '{print $1}' /etc/redhat-release`
    fi
  fi

  case $vendor in
    Ubuntu|Debian)
      fn="deploy_${1}_ubuntu"
      ;;
    CentOS|Red*)
      fn="deploy_${1}_rhel"
      ;;
    *)
      ;;
  esac
  if [ x"$(type -t $fn)" != x"function" ]; then
    fn="deploy_${1}"
  fi
  $fn
}
