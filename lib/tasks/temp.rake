# -*- coding: utf-8 -*-
namespace :temp do

  task :sync_xapian => :environment do
    InfoRequest.where(["updated_at >= ?", DateTime.new(2016, 2, 11, 9, 30)]).find_each do |info_request|
      info_request.reindex_request_events
    end

    User.where(["updated_at >= ?", DateTime.new(2016, 2, 11, 9, 30)]).find_each do |user|
      user.xapian_mark_needs_index
      user.reindex_referencing_models
    end

    PublicBody.where(["updated_at >= ?", DateTime.new(2016, 2, 11, 9, 30)]).find_each do |public_body|
      public_body.xapian_mark_needs_index
    end

  end


    desc 'Rewrite cached HTML attachment headers to use responsive CSS'
    task :responsive_attachments => :environment do
        example = 'rake responsive_attachments PATTERN="./cache/views/request/*/*/response/*/attach/html/*/*.html"'
        check_for_env_vars(['PATTERN'],example)
        pattern = ENV['PATTERN']
        replacement_head_content = <<-EOF
<!--[if LTE IE 7]>
<link href="/assets/responsive/application-lte-ie7.css" media="all" rel="stylesheet" title="Main" type="text/css" />
<![endif]-->

<!--[if IE 8]>
<link href="/assets/responsive/application-ie8.css" media="all" rel="stylesheet" title="Main" type="text/css" />
<![endif]-->

<!--[if GT IE 8]><!-->
<link href="/assets/responsive/application.css" media="all" rel="stylesheet" title="Main" type="text/css" />
<!--<![endif]-->

<script type="text/javascript" src="//use.typekit.net/csi1ugd.js"></script>
<script type="text/javascript">try{Typekit.load();}catch(e){}</script>
EOF


        Dir.glob(pattern) do |cached_html_file|
            puts cached_html_file
            text = File.read(cached_html_file)
            text.sub!(/<link [^>]*href="(\/assets\/application.css|\/stylesheets\/main.css|https?:\/\/www.whatdotheyknow.com\/stylesheets\/main.css)[^>]*>/, replacement_head_content)
            text.sub!(/<\/div>(\s*This is an HTML version of an attachment to the Freedom of Information request.*?)<\/div>/m, '</div><p class="view_html_description">\1</p></div>')
            text.sub!(/<iframe src='http:\/\/docs.google.com\/viewer/, "<iframe src='https://docs.google.com/viewer")
            text.sub!(/<\/head>/, '<meta name="viewport" content="width=device-width, initial-scale=1.0" /></head>')
            File.open(cached_html_file, 'w') { |file| file.write(text) }
        end
    end

  desc 'Analyse rails log specified by LOG_FILE to produce a list of request volume'
  task :request_volume => :environment do
    example = 'rake log_analysis:request_volume LOG_FILE=log/access_log OUTPUT_FILE=/tmp/log_analysis.csv'
    check_for_env_vars(['LOG_FILE', 'OUTPUT_FILE'],example)
    log_file_path = ENV['LOG_FILE']
    output_file_path = ENV['OUTPUT_FILE']
    is_gz = log_file_path.include?(".gz")
    urls = Hash.new(0)
    f = is_gz ? Zlib::GzipReader.open(log_file_path) : File.open(log_file_path, 'r')
    processed = 0
    f.each_line do |line|
      line.force_encoding('ASCII-8BIT')
      if request_match = line.match(/^Started (GET|OPTIONS|POST) "(\/request\/.*?)"/)
        next if line.match(/request\/\d+\/response/)
        urls[request_match[2]] += 1
        processed += 1
      end
    end
    url_counts = urls.to_a
    num_requests_visited_n_times = Hash.new(0)
    CSV.open(output_file_path, "wb") do |csv|
      csv << ['URL', 'Number of visits']
      url_counts.sort_by(&:last).each do |url, count|
        num_requests_visited_n_times[count] +=1
        csv << [url,"#{count}"]
      end
      csv << ['Number of visits', 'Number of URLs']
      num_requests_visited_n_times.to_a.sort.each do |number_of_times, number_of_requests|
        csv << [number_of_times, number_of_requests]
      end
      csv << ['Total number of visits']
      csv << [processed]
    end

  end

  desc 'Output all the requests made to the top 20 public bodies'
  task :get_top20_body_requests => :environment do

    require 'csv'
    puts CSV.generate_line(["public_body_id", "public_body_name", "request_created_timestamp", "request_title", "request_body"])

    PublicBody.limit(20).order('info_requests_visible_count DESC').each do |body|
      body.info_requests.where(:prominence => 'normal').find_each do |request|
        puts CSV.generate_line([request.public_body.id, request.public_body.name, request.created_at, request.url_title, request.initial_request_text.gsub("\r\n", " ").gsub("\n", " ")])
      end
    end

  end

  desc 'Look for and fix invalid UTF-8 text in various models. Should be run under ruby 1.9 or above'
  task :fix_invalid_utf8 => :environment do

    dryrun = ENV['DRYRUN'] != '0'
    if dryrun
      $stderr.puts "This is a dryrun - nothing will be changed"
    end


    PublicBody.find_each do |public_body|
      unless public_body.name.valid_encoding?
        name = convert_string_to_utf8(public_body.name)
        puts "Bad encoding in PublicBody name, id: #{public_body.id}, " \
          "old name: #{public_body.name.force_encoding('UTF-8')}, new name #{name}"
        unless dryrun
          public_body.name_will_change!
          public_body.name = name
          public_body.last_edit_editor = 'system'
          public_body.last_edit_comment = 'Invalid utf-8 encoding fixed by temp:fix_invalid_utf8'
          public_body.save!
        end
      end

      # Editing old versions of public bodies - we don't want to affect the timestamp
      PublicBody::Version.record_timestamps = false
      public_body.versions.each do |public_body_version|
        unless public_body_version.name.valid_encoding?
          name = convert_string_to_utf8(public_body_version.name).string
          puts "Bad encoding in PublicBody::Version name, " \
            "id: #{public_body_version.id}, old name: #{public_body_version.name.force_encoding('UTF-8')}, " \
            "new name: #{name}"
          unless dryrun
            public_body_version.name_will_change!
            public_body_version.name = name
            public_body_version.save!
          end
        end
      end
      PublicBody::Version.record_timestamps = true

    end

    IncomingMessage.find_each do |incoming_message|
      if (incoming_message.cached_attachment_text_clipped &&
        !incoming_message.cached_attachment_text_clipped.valid_encoding?) ||
          (incoming_message.cached_main_body_text_folded &&
           !incoming_message.cached_main_body_text_folded.valid_encoding?) ||
          (incoming_message.cached_main_body_text_unfolded &&
           !incoming_message.cached_main_body_text_unfolded.valid_encoding?)
          puts "Bad encoding in IncomingMessage cached fields, :id #{incoming_message.id} "
        unless dryrun
          incoming_message.clear_in_database_caches!
        end
      end
    end

    FoiAttachment.find_each do |foi_attachment|
      unescaped_filename = CGI.unescape(foi_attachment.filename)
      unless unescaped_filename.valid_encoding?
        filename = convert_string_to_utf8(unescaped_filename).string
        puts "Bad encoding in FoiAttachment filename, id: #{foi_attachment.id} " \
          "old filename #{unescaped_filename.force_encoding('UTF-8')}, new filename #{filename}"
        unless dryrun
          foi_attachment.filename = filename
          foi_attachment.save!
        end
      end
    end

    OutgoingMessage.find_each do |outgoing_message|
      unless outgoing_message.raw_body.valid_encoding?

        raw_body = convert_string_to_utf8(outgoing_message.raw_body).string
        puts "Bad encoding in OutgoingMessage raw_body, id: #{outgoing_message.id} " \
          "old raw_body: #{outgoing_message.raw_body.force_encoding('UTF-8')}, new raw_body: #{raw_body}"
        unless dryrun
          outgoing_message.body = raw_body
          outgoing_message.save!
        end
      end
    end

    User.find_each do |user|
      unless user.name.valid_encoding?
        name = convert_string_to_utf8(user.name).string
        puts "Bad encoding in User name, id: #{user.id}, " \
          "old name: #{user.name.force_encoding('UTF-8')}, new name: #{name}"
        unless dryrun
          user.name = name
          user.save!
        end
      end
    end

  end
end