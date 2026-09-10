FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
    && apt-get install -y --no-install-recommends iverilog verilator yosys make git ca-certificates \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /workspaces/ORX-1
