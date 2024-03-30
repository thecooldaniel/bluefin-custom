ARG BASE_IMAGE_NAME="${BASE_IMAGE_NAME:-silverblue}"
ARG IMAGE_FLAVOR="${IMAGE_FLAVOR:-main}"
ARG AKMODS_FLAVOR="${AKMODS_FLAVOR:-main}"
ARG SOURCE_IMAGE="${SOURCE_IMAGE:-$BASE_IMAGE_NAME-$IMAGE_FLAVOR}"
ARG BASE_IMAGE="ghcr.io/ublue-os/${SOURCE_IMAGE}"
ARG FEDORA_MAJOR_VERSION="${FEDORA_MAJOR_VERSION:-39}"
ARG TARGET_BASE="${TARGET_BASE:-bluefin}"

## bluefin image section
FROM ${BASE_IMAGE}:${FEDORA_MAJOR_VERSION} AS bluefin

ARG IMAGE_NAME="${IMAGE_NAME}"
ARG IMAGE_VENDOR="${IMAGE_VENDOR}"
ARG IMAGE_FLAVOR="${IMAGE_FLAVOR}"
ARG AKMODS_FLAVOR="${AKMODS_FLAVOR}"
ARG BASE_IMAGE_NAME="${BASE_IMAGE_NAME}"
ARG FEDORA_MAJOR_VERSION="${FEDORA_MAJOR_VERSION}"
ARG PACKAGE_LIST="bluefin"

# GNOME VRR & Ptyxis
RUN wget https://copr.fedorainfracloud.org/coprs/ublue-os/staging/repo/fedora-"${FEDORA_MAJOR_VERSION}"/ublue-os-staging-fedora-"${FEDORA_MAJOR_VERSION}".repo -O /etc/yum.repos.d/ublue-os-staging-fedora-"${FEDORA_MAJOR_VERSION}".repo && \
    if [ ${FEDORA_MAJOR_VERSION} -ge "39" ]; then \
        wget https://copr.fedorainfracloud.org/coprs/kylegospo/gnome-vrr/repo/fedora-"${FEDORA_MAJOR_VERSION}"/kylegospo-gnome-vrr-fedora-"${FEDORA_MAJOR_VERSION}".repo -O /etc/yum.repos.d/_copr_kylegospo-gnome-vrr.repo && \
        rpm-ostree override replace --experimental --from repo=copr:copr.fedorainfracloud.org:kylegospo:gnome-vrr mutter mutter-common gnome-control-center gnome-control-center-filesystem && \
        rm -f /etc/yum.repos.d/_copr_kylegospo-gnome-vrr.repo && \
        rpm-ostree override replace \
        --experimental \
        --from repo=copr:copr.fedorainfracloud.org:ublue-os:staging \
            gtk4 \
            vte291 \
            vte-profile \
            libadwaita && \
        rpm-ostree install \
            ptyxis \
    ; fi

# Install Explicit Sync Patches on Nvidia builds
RUN if [[ "${IMAGE_FLAVOR}" =~ "nvidia" ]]; then \
        wget https://copr.fedorainfracloud.org/coprs/gloriouseggroll/nvidia-explicit-sync/repo/fedora-$(rpm -E %fedora)/gloriouseggroll-nvidia-explicit-sync-fedora-$(rpm -E %fedora).repo?arch=x86_64 -O /etc/yum.repos.d/_copr_gloriouseggroll-nvidia-explicit-sync.repo && \
        rpm-ostree override replace \
        --experimental \
        --from repo=copr:copr.fedorainfracloud.org:gloriouseggroll:nvidia-explicit-sync \
            xorg-x11-server-Xwayland && \
        rpm-ostree override replace \
        --experimental \
        --from repo=copr:copr.fedorainfracloud.org:gloriouseggroll:nvidia-explicit-sync \
            egl-wayland \
            || true && \
        rm /etc/yum.repos.d/_copr_gloriouseggroll-nvidia-explicit-sync.repo \
    ; fi

COPY usr /usr
COPY just /tmp/just
COPY etc/yum.repos.d/ /etc/yum.repos.d/
COPY packages.json /tmp/packages.json
COPY build.sh /tmp/build.sh
COPY image-info.sh /tmp/image-info.sh
COPY install-akmods.sh /tmp/install-akmods.sh
COPY fetch-quadlets.sh /tmp/fetch-quadlets.sh
# Copy ublue-update.toml to tmp first, to avoid being overwritten.
COPY usr/etc/ublue-update/ublue-update.toml /tmp/ublue-update.toml

# Add ublue kmods, add needed negativo17 repo and then immediately disable due to incompatibility with RPMFusion
COPY --from=ghcr.io/ublue-os/akmods:${AKMODS_FLAVOR}-${FEDORA_MAJOR_VERSION} /rpms /tmp/akmods-rpms
RUN /tmp/install-akmods.sh && \
    wget https://copr.fedorainfracloud.org/coprs/che/nerd-fonts/repo/fedora-"${FEDORA_MAJOR_VERSION}"/che-nerd-fonts-fedora-"${FEDORA_MAJOR_VERSION}".repo -O /etc/yum.repos.d/_copr_che-nerd-fonts-"${FEDORA_MAJOR_VERSION}".repo

# Starship Shell Prompt
RUN curl -Lo /tmp/starship.tar.gz "https://github.com/starship/starship/releases/latest/download/starship-x86_64-unknown-linux-gnu.tar.gz" && \
  tar -xzf /tmp/starship.tar.gz -C /tmp && \
  install -c -m 0755 /tmp/starship /usr/bin && \
  echo 'eval "$(starship init bash)"' >> /etc/bashrc

# Copy Bluefin CLI packages
COPY --from=ghcr.io/ublue-os/bluefin-cli /usr/bin/atuin /usr/bin/atuin
COPY --from=ghcr.io/ublue-os/bluefin-cli /usr/share/bash-prexec /usr/share/bash-prexec
COPY --from=ghcr.io/ublue-os/bluefin-cli /usr/bin/eza /usr/bin/eza
COPY --from=ghcr.io/ublue-os/bluefin-cli /usr/bin/fd /usr/bin/fd
COPY --from=ghcr.io/ublue-os/bluefin-cli /usr/bin/fzf /usr/bin/fzf
COPY --from=ghcr.io/ublue-os/bluefin-cli /usr/bin/rg /usr/bin/rg
COPY --from=ghcr.io/ublue-os/bluefin-cli /usr/bin/zoxide /usr/bin/zoxide

RUN wget https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh -O /usr/libexec/brew-install && \
    chmod +x /usr/libexec/brew-install && \
    /tmp/build.sh && \
    /tmp/image-info.sh && \
    /tmp/fetch-quadlets.sh && \
    pip install --prefix=/usr topgrade && \
    rpm-ostree install ublue-update && \
    mkdir -p /usr/etc/flatpak/remotes.d && \
    wget -q https://dl.flathub.org/repo/flathub.flatpakrepo -P /usr/etc/flatpak/remotes.d && \
    cp /tmp/ublue-update.toml /usr/etc/ublue-update/ublue-update.toml && \
    if [[ "${FEDORA_MAJOR_VERSION}" -ge "39" ]]; then \
        systemctl enable tuned.service \
    ; fi && \
    systemctl enable rpm-ostree-countme.service && \
    systemctl enable tailscaled.service && \
    systemctl enable dconf-update.service && \
    systemctl --global enable ublue-flatpak-manager.service && \
    systemctl enable ublue-update.timer && \
    systemctl enable ublue-system-setup.service && \
    systemctl --global enable ublue-user-setup.service && \
    fc-cache -f /usr/share/fonts/ubuntu && \
    fc-cache -f /usr/share/fonts/inter && \
    find /tmp/just -iname '*.just' -exec printf "\n\n" \; -exec cat {} \; >> /usr/share/ublue-os/just/60-custom.just && \
    rm -f /etc/yum.repos.d/tailscale.repo && \
    rm -f /etc/yum.repos.d/charm.repo && \
    rm -f /etc/yum.repos.d/ublue-os-staging-fedora-"${FEDORA_MAJOR_VERSION}".repo && \
    echo "Hidden=true" >> /usr/share/applications/fish.desktop && \
    echo "Hidden=true" >> /usr/share/applications/htop.desktop && \
    echo "Hidden=true" >> /usr/share/applications/nvtop.desktop && \
    echo "Hidden=true" >> /usr/share/applications/gnome-system-monitor.desktop && \
    rm -f /etc/yum.repos.d/_copr_che-nerd-fonts-"${FEDORA_MAJOR_VERSION}".repo && \
    sed -i 's/#DefaultLimitNOFILE=/DefaultLimitNOFILE=4096:524288/' /etc/systemd/user.conf && \
    sed -i 's/#DefaultTimeoutStopSec.*/DefaultTimeoutStopSec=15s/' /etc/systemd/user.conf && \
    sed -i 's/#DefaultTimeoutStopSec.*/DefaultTimeoutStopSec=15s/' /etc/systemd/system.conf && \
    sed -i '/^PRETTY_NAME/s/Silverblue/Bluefin/' /usr/lib/os-release && \
    rm -rf /tmp/* /var/* && \
    ostree container commit && \
    mkdir -p /var/tmp && \
    chmod -R 1777 /var/tmp

## bluefin-dx developer edition image section
FROM bluefin AS bluefin-dx

ARG IMAGE_NAME="${IMAGE_NAME}"
ARG IMAGE_VENDOR="${IMAGE_VENDOR}"
ARG BASE_IMAGE_NAME="${BASE_IMAGE_NAME}"
ARG IMAGE_FLAVOR="${IMAGE_FLAVOR}"
ARG FEDORA_MAJOR_VERSION="${FEDORA_MAJOR_VERSION}"
ARG PACKAGE_LIST="bluefin-dx"

# dx specific files come from the dx directory in this repo
COPY dx/usr /usr
COPY dx/etc/yum.repos.d/ /etc/yum.repos.d/
COPY workarounds.sh \
     packages.json \
     build.sh \
     image-info.sh \
    /tmp

# Apply IP Forwarding before installing Docker to prevent messing with LXC networking
RUN sysctl -p

RUN wget https://copr.fedorainfracloud.org/coprs/ganto/lxc4/repo/fedora-"${FEDORA_MAJOR_VERSION}"/ganto-lxc4-fedora-"${FEDORA_MAJOR_VERSION}".repo -O /etc/yum.repos.d/ganto-lxc4-fedora-"${FEDORA_MAJOR_VERSION}".repo && \
    wget https://copr.fedorainfracloud.org/coprs/ublue-os/staging/repo/fedora-"${FEDORA_MAJOR_VERSION}"/ublue-os-staging-fedora-"${FEDORA_MAJOR_VERSION}".repo -O /etc/yum.repos.d/ublue-os-staging-fedora-"${FEDORA_MAJOR_VERSION}".repo && \
    wget https://copr.fedorainfracloud.org/coprs/karmab/kcli/repo/fedora-"${FEDORA_MAJOR_VERSION}"/karmab-kcli-fedora-"${FEDORA_MAJOR_VERSION}".repo -O /etc/yum.repos.d/karmab-kcli-fedora-"${FEDORA_MAJOR_VERSION}".repo && \
    wget https://copr.fedorainfracloud.org/coprs/atim/ubuntu-fonts/repo/fedora-"${FEDORA_MAJOR_VERSION}"/atim-ubuntu-fonts-fedora-"${FEDORA_MAJOR_VERSION}".repo -O /etc/yum.repos.d/atim-ubuntu-fonts-fedora-"${FEDORA_MAJOR_VERSION}".repo

# Handle packages via packages.json
RUN /tmp/build.sh && \
    /tmp/image-info.sh

COPY --from=cgr.dev/chainguard/dive:latest /usr/bin/dive /usr/bin/dive
COPY --from=cgr.dev/chainguard/flux:latest /usr/bin/flux /usr/bin/flux
COPY --from=cgr.dev/chainguard/helm:latest /usr/bin/helm /usr/bin/helm
COPY --from=cgr.dev/chainguard/ko:latest /usr/bin/ko /usr/bin/ko
COPY --from=cgr.dev/chainguard/minio-client:latest /usr/bin/mc /usr/bin/mc
COPY --from=cgr.dev/chainguard/kubectl:latest /usr/bin/kubectl /usr/bin/kubectl

RUN curl -Lo ./kind "https://github.com/kubernetes-sigs/kind/releases/latest/download/kind-$(uname)-amd64" && \
    chmod +x ./kind && \
    mv ./kind /usr/bin/kind

# Install kns/kctx and add completions for Bash
RUN wget https://raw.githubusercontent.com/ahmetb/kubectx/master/kubectx -O /usr/bin/kubectx && \
    wget https://raw.githubusercontent.com/ahmetb/kubectx/master/kubens -O /usr/bin/kubens && \
    chmod +x /usr/bin/kubectx /usr/bin/kubens

# Set up services
# Removed: systemctl disable pmie.service && \
#          systemctl disable pmlogger.service
RUN systemctl enable docker.socket && \
    systemctl enable podman.socket && \
    systemctl enable swtpm-workaround.service && \
    systemctl enable bluefin-dx-groups.service && \
    systemctl enable --global bluefin-dx-user-vscode.service

RUN /tmp/workarounds.sh

# Clean up repos, everything is on the image so we don't need them
RUN rm -f /etc/yum.repos.d/ublue-os-staging-fedora-"${FEDORA_MAJOR_VERSION}".repo && \
    rm -f /etc/yum.repos.d/ganto-lxc4-fedora-"${FEDORA_MAJOR_VERSION}".repo && \
    rm -f /etc/yum.repos.d/karmab-kcli-fedora-"${FEDORA_MAJOR_VERSION}".repo && \
    rm -f /etc/yum.repos.d/atim-ubuntu-fonts-fedora-"${FEDORA_MAJOR_VERSION}".repo && \
    rm -f /etc/yum.repos.d/vscode.repo && \
    rm -f /etc/yum.repos.d/docker-ce.repo && \
    rm -f /etc/yum.repos.d/_copr:copr.fedorainfracloud.org:phracek:PyCharm.repo && \
    rm -f /etc/yum.repos.d/fedora-cisco-openh264.repo && \
    fc-cache --system-only --really-force --verbose && \
    rm -rf /tmp/* /var/* && \
    ostree container commit
