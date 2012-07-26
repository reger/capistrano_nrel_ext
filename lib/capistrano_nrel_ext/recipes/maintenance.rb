require "chronic"
require "tzinfo"

require "capistrano_nrel_ext/actions/sample_files"

Capistrano::Configuration.instance(true).load do
  #
  # Variables
  #
  set :maintenance_type, "general"
  set :maintenance_reason, "maintenance"
  set :maintenance_starting, ""
  set :maintenance_ending, "shortly"

  #
  # Tasks
  #
  namespace :deploy do
    namespace :web do
      desc <<-DESC
        Present a maintenance page to visitors. Disables your application's web \
        interface by writing a "maintenance.html" file to each web server. The \
        servers must be configured to detect the presence of this file, and if \
        it is present, always display it instead of performing the request.

        By default, the maintenance page will just say the site is down for \
        "maintenance", and will be back "shortly", but you can customize the \
        page by specifying the REASON and UNTIL environment variables:

          $ cap deploy:web:disable \\
                REASON="hardware upgrade" \\
                UNTIL="12pm Central Time"

        Further customization will require that you write your own task.
      DESC
      task :disable, :roles => :web, :except => { :no_release => true } do
        on_rollback { run "rm -f #{shared_path}/public/system/maintenance.html && rm -f #{shared_path}/public/system/maintenance_#{maintenance_type}" }

        warn <<-EOHTACCESS
        
          # Please add something like this to your site's htaccess to redirect users to the maintenance page.
          # More Info: http://www.shiftcommathree.com/articles/make-your-rails-maintenance-page-respond-with-a-503
          
          ErrorDocument 503 /system/maintenance.html
          RewriteEngine On
          RewriteCond %{REQUEST_URI} !\.(css|gif|jpg|png)$
          RewriteCond %{DOCUMENT_ROOT}/system/maintenance.html -f
          RewriteCond %{SCRIPT_FILENAME} !maintenance.html
          RewriteRule ^.*$  -  [redirect=503,last]
        EOHTACCESS

        if ENV["REASON"]
          set(:maintenance_reason, ENV["REASON"])
        end

        # Give all times in the Eastern time zone (since more people are
        # probably used to seeing it than mountain).
        time_zone = TZInfo::Timezone.get("America/New_York")
        time_format = "%A, %B %e, %Y, %l:%M %p %Z"

        # If a custom end time is given in the UNTIL environment variable, use
        # chronic to parse it, so it can be given in more natural terms, but we
        # can convert it to a true time in the eastern time zone.
        if ENV["UNTIL"]
          parsed_time = Chronic.parse(ENV["UNTIL"])
          if parsed_time
            set(:maintenance_ending, time_zone.strftime(time_format, parsed_time.utc))
          else
            raise Capistrano::Error, "Unable to parse `UNTIL` variable: #{ENV["UNTIL"].inspect}. UNTIL should be a local time string, e.g., \"8PM\" or \"01/28/2012 8:00PM\""
          end
        end

        # Estimate the starting time for display in the confirmation message.
        set(:maintenance_starting, time_zone.strftime(time_format, Time.now.utc))

        logger.info("\nMaintenance Reason: #{maintenance_reason.inspect}")
        logger.info("Maintenance Starting: #{maintenance_starting.inspect}")
        logger.info("Maintenance Estimated Ending: #{maintenance_ending.inspect}\n\n")

        confirm = Capistrano::CLI.ui.ask("Are you sure you want to put the website into maintenance mode? (y/n) ") do |q|
          q.default = "n"
        end.downcase

        if(confirm == "y")
          # Redefine the starting time (in case the original estimate is now
          # wrong from the user sitting at the y/n prompt for a long time).
          set(:maintenance_starting, time_zone.strftime(time_format, Time.now.utc))

          parse_sample_files(["config/templates/maintenance.html"])
          run "mv #{File.join(latest_release, "config", "templates", "maintenance.html")} #{File.join(shared_path, "public", "system", "maintenance.html")}"
          run "touch #{File.join(shared_path, "public", "system", "maintenance_#{maintenance_type}")}"

          # If Varnish is being used, clear its cache.
          if(exists?(:varnish_ban_script))
            varnish.ban
          end
        end
      end

      desc <<-DESC
        Makes the application web-accessible again. Removes the \
        "maintenance.html" page generated by deploy:web:disable, which (if your \
        web servers are configured correctly) will make your application \
        web-accessible again.
      DESC
      task :enable, :roles => :web, :except => { :no_release => true } do
        run "rm -f #{shared_path}/public/system/maintenance.html && rm -f #{shared_path}/public/system/maintenance_#{maintenance_type}"

        # If Varnish is being used, clear its cache.
        if(exists?(:varnish_ban_script))
          varnish.ban
        end
      end

      desc <<-DESC
        Present a maintenance page to visitors for data-input pages.
      DESC
      task :disable_input, :roles => :web, :except => { :no_release => true } do
        set :maintenance_type, "input"
        deploy.web.disable
      end

      desc <<-DESC
        Makes the data-input pages web-accessible again.
      DESC
      task :enable_input, :roles => :web, :except => { :no_release => true } do
        set :maintenance_type, "input"
        deploy.web.enable
      end
    end
  end
end
