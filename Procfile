web: bundle exec puma -C config/puma.rb -e production
# worker: SIDEKIQ_CONCURRENCY=${SIDEKIQ_WORKER_CONCURRENCY:-$SIDEKIQ_CONCURRENCY} RAILS_MAX_THREADS=${SIDEKIQ_WORKER_CONCURRENCY:-$RAILS_MAX_THREADS} bundle exec sidekiq -C ./config/sidekiq.yml -e ${RAILS_ENV:-development}
# batches: SIDEKIQ_CONCURRENCY=${SIDEKIQ_BATCHES_CONCURRENCY:-$SIDEKIQ_CONCURRENCY} RAILS_MAX_THREADS=${SIDEKIQ_BATCHES_CONCURRENCY:-$RAILS_MAX_THREADS} bundle exec sidekiq -C ./config/sidekiq_batches.yml -e ${RAILS_ENV:-development}
release: lib/sh/heroku_deploy.sh