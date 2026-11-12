# Der Simulator im Container (#533, tool/garmin_sim.sh): das Bild eines
# Dritten (nicht von Garmin; Connect IQ SDK 9.2.0, Linux-Simulator, Xvfb,
# Geräte inkl. fenix5/5plus/5s/5x; nur amd64), festgenagelt per Digest —
# HIER und nur hier. Darauf nur, was das Skript braucht: xdotool für
# Klicks und Tasten, UTF-8 für die Konsole (sonst „???" statt „→").
#
# Wird lokal von `tool/garmin_sim.sh up` gebaut, nie veröffentlicht: Wir
# verteilen kein Garmin-SDK aus diesem Repo.
ARG BASE=ghcr.io/matco/connectiq-tester@sha256:64958e8fd2925d0c4986d72a9aa9d8e2101297a881354aab0118be2f1dc22105
FROM ${BASE}
RUN apt-get update -qq \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends xdotool \
 && rm -rf /var/lib/apt/lists/*
ENV LANG=C.UTF-8 LC_ALL=C.UTF-8
