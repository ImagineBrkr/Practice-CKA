#!/bin/bash

source ./.env

export TG_WORKING_DIR=$PWD/infra/terragrunt-deploy
export TG_NO_AUTO_INIT=true

terragrunt init --all

terragrunt plan --all