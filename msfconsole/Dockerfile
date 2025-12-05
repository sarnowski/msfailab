FROM kalilinux/kali-rolling

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
    kali-linux-headless \
    metasploit-framework \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*
