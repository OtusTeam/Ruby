FROM ruby:3.2.2

ADD . /app
WORKDIR /app

RUN bundle install

EXPOSE 3000

CMD ["bash", "/app/scripts/run_puma.sh"]