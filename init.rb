# TODO:
# Support versions and milestones

require 'rubygems'
require 'active_resource'
require 'appscript'
include Appscript
require "pp"
require "yaml"

CONFIG = YAML::load(File.open(File.expand_path('../config.yml', __FILE__)))
Things = app("Things")

class Issue < ActiveResource::Base
	CONFIG.each { |k,v| self.send("#{k.to_s}=".to_sym,v) }
end

class Project < ActiveResource::Base
	CONFIG.each { |k,v| self.send("#{k.to_s}=".to_sym,v) }
end

@priorities = {
	'Low' 			=> 3,	
	'Normal' 		=> 4,
	'Medium' 		=> 4,
	'High' 			=> 5,
	'Urgent' 		=> 6,
	'Immediate' => 7
}

@trackers = {
	'Bug'				=> 1,
	'Feature' 	=> 2,
	'Support' 	=> 3,
	'Idea' 			=> 4 # custom
}

@issue_statuses = {
	'New'         => 1,
	'In Progress' => 2,
	'Resolved'  	=> 3,
	'Feedback'  	=> 4,
	'Closed'    	=> 5,
	'Rejected'		=> 6
}

@completed_statuses = ['Resolved', 'Closed', 'Rejected']

def pull_projects  
  @redmine_projects = Project.find(:all)
  @things_projects = Things.projects.get()
  @things_projects_collected = @things_projects.collect {|project| project.name.get()}
  @redmine_projects.each do |project|
    if @things_projects_collected.index(project.name).nil?
      Things.make(:new => :project, :with_properties => {:name => project.name})
    end
  end
end

def tagline(issue)
	tags = []
	if issue.priority.name != "Normal"
		tags << issue.priority.name
	end
	tags << issue.tracker.name
	tags << 'redmine'
	tags.join ','
end

def pull_issues
  @redmine_issues = Issue.find(:all)
  @redmine_issues.each do |rs|
		puts "Updating #{rs.subject} (#{rs.id})"      
		to_dos = Things.tags['redmine'].get.to_dos.get
		to_do = to_dos.select { |td| td.notes.get =~ /Issue: ##{rs.id}/ }.first

		unless to_do
			puts "\tis a new task"
			to_do = Things.make(:new => :to_do, 
				:with_properties =>{
		   		:name => rs.subject
		  	}
			)
		
			unless rs.save
	    	puts rs.errors.full_messages
	  	end
		
			to_do.project.set(Things.projects[rs.project.name])				
			to_do.tag_names.set(tagline(rs))			
			to_do.name.set(rs.subject)			

			notes = (rs.description || "") + "\nIssue: ##{rs.id}"
			to_do.notes.set(notes)
		end

		to_do.project.set(Things.projects[rs.project.name])
		to_do.tag_names.set(tagline(rs) + ", " + to_do.tag_names.get)		

    if @completed_statuses.include? rs.status.name
			puts "\t...closed"
      to_do.status.set(:completed)
    end
  end
end

def push_issues
  puts "Pushing Issues"
  to_dos = Things.tags['redmine'].get.to_dos.get
  to_dos.each do |to_do|
    path = to_do.inspect.split('.')
    if path[2] == "projects"
    else
			to_do.notes.get =~ /Issue: #(\d+)/
			issue_id = $1
			issue = nil
			unless issue_id
				project_name = to_do.project.get.name.get
				project = @redmine_projects.select {|p| p.name == project_name}.first
				if project
					puts "Creating issue #{to_do.name.get}"
					issue = Issue.create :subject => to_do.name.get,
											 				 :project_id => project.id,
											         :description => to_do.notes.get
											
					t = "#{to_do.notes.get}\nIssue: ##{issue.id}"
					to_do.notes.set(t)											
				else
					puts "Unknown redmine project #{project_name}"
					next
				end
			else
				issue = Issue.find(issue_id)
			end
			
			tags = to_do.tag_names.get.split(',').map(&:strip)
			@priorities.each do |name, id|
				if tags.include? name
					issue.priority_id = id
					break
				end
			end
			
			@trackers.each do |name, id|
				if tags.include? name
					issue.tracker_id = id
					break
				end
			end
			
			if to_do.status.get.to_s == "completed"
        issue.status_id = @issue_statuses['Resolved'] unless @completed_statuses.include? issue.status.name
      end			

			if !issue.save
        puts issue.errors.full_messages
      end

    end
  end
end

pull_projects
push_issues
pull_issues