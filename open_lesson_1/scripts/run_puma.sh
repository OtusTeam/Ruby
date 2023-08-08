#!/bin/bash

if [[ ! -z "$CREATE_DB_ON_INIT" ]]; then
  bin/rails db:create
fi

bin/rails db:migrate db:seed
bin/bundle exec puma -C config/puma.rb
