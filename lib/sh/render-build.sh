#!/usr/bin/env bash
# exit on error
set -o errexit

bundle install

# If you're using a Free instance type, you need to
# perform database migrations in the build command.
# Uncomment the following line:

# bundle exec rails db:migrate


# bundle exec puma -t 5:5 -p ${PORT:-3000} -e ${RACK_ENV:-development}