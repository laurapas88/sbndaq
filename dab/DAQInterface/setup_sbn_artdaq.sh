#!/usr/bin/env bash
source /software/products/setup
[[ -f /software/products_dev/setup ]] && source /software/products_dev/setup

setup sbndaq v0_05_00 -q e19:prof:s87
setup artdaq_daqinterface v3_07_02

