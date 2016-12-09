namespace :weekly do
  desc "Create weekly with scaffold"
  task :create, [:date] do |t, args|
    args.with_defaults(:date => Time.now.strftime("%Y-%m-%d"))
    weekly_date = args[:date]
    weekly_html_file = "_weekly/#{weekly_date}-weekly.md"
    weekly_email_file = "_newsletter/#{weekly_date}-weekly-email.md"

    weekly_frontmatter = "---\ndatasrc: #{weekly_date}-weekly\n---"
    weekly_content = <<-EOF
---
articles:
  - title:    "Your Awesome Article Title"
    link:     "https://msbu-tech.github.io/"
    comment:  "The reason why you recommend this article."
    referrer: "Your Name"
    tags:    ["tag"]
---
    EOF

    File.new(weekly_html_file, "w").syswrite(weekly_content)
    File.new(weekly_email_file, "w").syswrite(weekly_content)
  end

  desc "Open weekly issue"
  task :open, [:date] do |t, args|
    args.with_defaults(:date => Time.now.strftime("%Y-%m-%d"))
    weekly_date = args[:date]

    open_issue(weekly_date)
  end

  desc "Publish weekly"
  task :publish, [:date] do |t, args|
    args.with_defaults(:date => "latest")
    weekly_date = args[:date]
    weekly_date = find_latest_weekly.split("-weekly.md").at(0) if weekly_date == "latest"

    say_thanks_and_close_issue(weekly_date)
  end

  desc "Import weekly articles"
  task :import, [:date] do |t, args|
    args.with_defaults(:date => Time.now.strftime("%Y-%m-%d"))
    weekly_date = args[:date]
    weekly_html_file = "_weekly/#{weekly_date}-weekly.md"
    weekly_email_file = "_newsletter/#{weekly_date}-weekly-email.md"
    # do import from github issues
    articles = import_articles_from_issues("#{weekly_date} 文章收集")
    if articles == false
      puts "[ERROR] Import articles error!".red
      exit 1
    end
    weekly_content = "---\narticles:\n"
    articles.each do |item|
      weekly_content << "  - title:    \"#{item[:title]}\"\n"
      weekly_content << "    link:     \"#{item[:link]}\"\n"
      weekly_content << "    referrer: \"#{item[:referrer]}\"\n"
      weekly_content << "    comment:  \"#{item[:comment]}\"\n"
      tags = Array.new
      item[:tags].split(",").each do |tag|
        tags << "\"#{tag.strip}\""
      end
      weekly_content << "    tags:    [#{tags.join(", ")}]\n"
    end
    weekly_content << "---\n"
    weekly_frontmatter = "---\ndatasrc: #{weekly_date}-weekly\n---"

    File.new(weekly_html_file, "w").syswrite(weekly_content)
    File.new(weekly_email_file, "w").syswrite(weekly_frontmatter)
  end

  desc "Edit the latest weekly"
  task "edit-latest" do
    latest = find_latest_weekly
    sh "$EDITOR _weekly/#{latest}"
  end
end

def import_articles_from_issues(issue_name)
  return false if issue_name.empty?

  repo_name = "msbu-tech/weekly".freeze

  client = Octokit::Client.new(:access_token => get_access_token)

  # find issue
  issues = client.list_issues(repo_name, options = {:state => "open"})
  number = 0
  issues.each do |issue|
    if issue[:title].eql? issue_name
      number = issue[:number]
      break
    end
  end
  # fetch issue comment
  issue_comment = client.issue_comments(repo_name, number)
  # iterate issue comment to import articles
  articles = Array.new
  issue_comment.each do |item|
    body = item[:body]
    title = ""
    link = ""
    comment = ""
    tags = Array.new
    referrer = item[:user][:login]
    body.split("\r\n").each_with_index do |line, i|
      case i
      when 0
        if !line.strip.eql?("/post")
          puts "[INFO] Skip comment #{number}:#{item[:id]}".green
          break
        end
      when 1
        title = Spacifier.spacify(line.strip.split("- ").at(1))
      when 2
        link = line.strip.split("- ").at(1)
      when 3
        comment = Spacifier.spacify(line.strip.split("- ").at(1))
      when 4
        tags = line.strip.split("- ").at(1)
        articles << { :title => title, :link => link, :comment => comment, :tags => tags, :referrer => referrer }
      end
    end
  end

  puts "[INFO] Import #{articles.count} article(s)".green
  articles
end

def say_thanks_and_close_issue(weekly_date)
  issue_name = "#{weekly_date} 文章收集"
  repo_name = "msbu-tech/weekly".freeze

  client = Octokit::Client.new(:access_token => get_access_token)
  # find issue
  issues = client.list_issues(repo_name, options = {:state => "open"})
  number = 0
  issues.each do |issue|
    if issue[:title].eql? issue_name
      number = issue[:number]
      break
    end
  end
  # fetch issue comment
  issue_comment = client.issue_comments(repo_name, number)
  # collect contributors
  contributors = Hash.new
  issue_comment.each do |item|
    if item[:body].strip.start_with?("/post")
      contributors[item[:user][:login]] = 1
    end
  end
  contributors_list = []
  contributors.each_key do |key|
    contributors_list << "@#{key}"
  end
  comment = "Congratulations!\nMSBU Weekly #{weekly_date} is published on <https://msbu-tech.github.io/weekly/#{weekly_date}-weekly.html>!\nThanks #{contributors_list.join ', '} for your great contribution!"
  client.add_comment(repo_name, number, comment)
  client.close_issue(repo_name, number)
  # commit
  msg = "Weekly #{weekly_date} published"
  sh "git add ."
  sh "git commit -m #{msg}"
  sh "git push"

  puts "Success."
end

def open_issue(weekly_date)
  issue_name = "#{weekly_date} 文章收集"
  repo_name = "msbu-tech/weekly".freeze

  client = Octokit::Client.new(:access_token => get_access_token)
  client.create_issue(repo_name, issue_name, "MSBU Weekly #{weekly_date} is now in collecting. Post your entry following the instruction of <https://github.com/msbu-tech/weekly#投稿>.")

  puts "Success."
end