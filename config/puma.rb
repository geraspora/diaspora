require File.expand_path('../load_config', __FILE__)

pidfile '/var/run/diaspora/diaspora.pid'
bind 'unix:///var/run/diaspora/diaspora.sock'

worker_timeout AppConfig.server.unicorn_timeout.to_i

stdout_redirect AppConfig.server.stdout_log? ? AppConfig.server.stdout_log.get : '/dev/null',
                AppConfig.server.stderr_log? ? AppConfig.server.stderr_log.get : '/dev/null'

workers 8
preload_app!
