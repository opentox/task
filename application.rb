require 'rubygems'
gem "opentox-ruby", "~> 3"
require 'opentox-ruby'

set :lock, true

class Task < Ohm::Model
	
	attribute :uri
  attribute :created_at

  attribute :finished_at
  attribute :due_to_time
  attribute :pid

  attribute :resultURI
  attribute :percentageCompleted
  attribute :hasStatus
  attribute :title
  attribute :creator
  attribute :description

  attribute :waiting_for

  attribute :error_report_yaml
  
  # convenience method to store object in redis
  def errorReport
    YAML.load(self.error_report_yaml) if self.error_report_yaml
  end

  # convenience method to store object in redis
  def errorReport=(er)
    self.error_report_yaml = er.to_yaml
  end
  

  def metadata
    {
      DC.creator => creator,
      DC.title => title,
      DC.date => created_at,
      OT.hasStatus => hasStatus,
      OT.resultURI => resultURI,
      OT.percentageCompleted => percentageCompleted.to_f,
      #text fields are lazy loaded, using member variable can cause description to be nil
      DC.description => description   
      #:due_to_time => @due_to_timer
    }
  end

end

#DataMapper.auto_upgrade!

# Get a list of all tasks
# @return [text/uri-list] List of all tasks
get '/?' do
	LOGGER.debug "list all tasks "+params.inspect
  if request.env['HTTP_ACCEPT'] =~ /html/
    response['Content-Type'] = 'text/html'
    OpenTox.text_to_html Task.all.sort.collect{|t| t.uri}.join("\n") + "\n"
  else
    response['Content-Type'] = 'text/uri-list'
    Task.all.collect{|t| t.uri}.join("\n") + "\n"
  end
end

get '/latest' do
  response['Content-Type'] = 'text/plain'
  ts = Task.all.sort
  running = []
  ts.size.times do |i|
    t = ts[ts.size-(i+1)]
    if Time.now - Time.parse(t.created_at) > 60*60*24
      break
    elsif t.hasStatus=="Running"
      running << t
    end
  end
  running.reverse!
  running << ts[-1] if running.size==nil or running[-1]!=ts[-1]
  running.collect{|t| "'#{t.uri}' --- '#{t.created_at}' --- '#{t.hasStatus}' --- '#{t.title}'"}.join("\n")+"\n"
end

# Get task representation
# @param [Header] Accept Mime type of accepted representation, may be one of `application/rdf+xml,application/x-yaml,text/uri-list`
# @return [application/rdf+xml,application/x-yaml,text/uri-list] Task representation in requested format, Accept:text/uri-list returns URI of the created resource if task status is "Completed"
get '/:id/?' do
  task = Task[params[:id]]
  raise OpenTox::NotFoundError.new "Task '#{params[:id]}' not found." unless task
  
  # set task http code according to status
  case task.hasStatus
  when "Running"
    code = 202
  when "Cancelled"
    code = 503
  when "Error"
    if task.errorReport
       code = task.errorReport.http_code.to_i
    else
     code = 500
    end
  else #Completed
    code = 200
  end
  
  case request.env['HTTP_ACCEPT']
  when /yaml/ 
    response['Content-Type'] = 'application/x-yaml'
    metadata = task.metadata
    metadata[OT.waitingFor] = task.waiting_for
    metadata[OT.errorReport] = task.errorReport if task.errorReport
    metadata["PID"] = task.pid
    halt code, metadata.to_yaml
    #halt code, task.created_at
  when /html/
    response['Content-Type'] = 'text/html'
    metadata = task.metadata
    description = task.title ? "This task computes '"+task.title+"'" : "This task performs a process that is running on the server."
    if task.hasStatus=="Running"
      description << "\nRefresh your browser (presss F5) to see if the task has finished."
    elsif task.hasStatus=="Completed"
      description << "\nThe task is completed, click on the link below to see your result."
    elsif task.errorReport
      description << "\nUnfortunately, the task has failed."
    end
    related_links = task.hasStatus=="Completed" ? "The task result: "+task.resultURI : nil
    metadata[OT.waitingFor] = task.waiting_for
    metadata[OT.errorReport] = task.errorReport if task.errorReport
    task.inspect # to load all stuff for to_yaml
    halt code, OpenTox.text_to_html([metadata,task].to_yaml, @subjectid, related_links, description)    
  when /application\/rdf\+xml|\*\/\*/ # matches 'application/x-yaml', '*/*'
    response['Content-Type'] = 'application/rdf+xml'
    t = OpenTox::Task.new task.uri
    t.add_metadata task.metadata
    t.add_error_report task.errorReport if task.errorReport
    halt code, t.to_rdfxml
  when /text\/uri\-list/
    response['Content-Type'] = 'text/uri-list'
    if task.hasStatus=="Completed"
      halt code, task.resultURI
    else
      halt code, task.uri
    end
  else
    raise OpenTox::BadRequestError.new "MIME type '"+request.env['HTTP_ACCEPT'].to_s+"' not supported, valid Accept-Headers are \"application/rdf+xml\" and \"application/x-yaml\"."
  end
end


# Get Task properties. Works for
# - /task/id
# - /task/uri
# - /task/created_at
# - /task/finished_at
# - /task/due_to_time
# - /task/pid
# - /task/resultURI
# - /task/percentageCompleted
# - /task/hasStatus
# - /task/title
# - /task/creator
# - /task/description
# @return [String] Task property
get '/:id/:property/?' do
	response['Content-Type'] = 'text/plain'
  task = Task[params[:id]]
  raise OpenTox::NotFoundError.new"Task #{params[:id]} not found." unless task
  begin
    eval("task.#{params[:property]}").to_s
  rescue
    raise OpenTox::NotFoundError.new"Unknown task property #{params[:property]}."
  end
end

# Create a new task
# @param [optional,String] max_duration
# @param [optional,String] pid
# @param [optional,String] resultURI
# @param [optional,String] percentageCompleted
# @param [optional,String] hasStatus
# @param [optional,String] title
# @param [optional,String] creator
# @param [optional,String] description
# @return [text/uri-list] URI for new task
post '/?' do
  LOGGER.debug "Creating new task with params "+params.inspect
  max_duration = params.delete(:max_duration.to_s) if params.has_key?(:max_duration.to_s)
  params[:created_at] = Time.now
  params[:hasStatus] = "Running" unless params[:hasStatus]
  task = Task.create params
  task.update :uri => url_for("/#{task.id}", :full)
  #task.due_to_time = DateTime.parse((Time.parse(task.created_at.to_s) + max_duration.to_f).to_s) if max_duration
  #raise "Could not save task #{task.uri}" unless task.save
  response['Content-Type'] = 'text/uri-list'
  task.uri + "\n"
end

# Clean tasks. Delete every completed task older than 30 days
delete '/cleanup' do
  begin
    tasklist = Task.all
    tasklist.each do |task|
      if task.metadata[OT.hasStatus] == 'Completed'
        LOGGER.debug "deleting: #{task.id}"
        task.delete if Time.now - Time.parse(task.created_at) > (2592000/30)
      end
    end
  rescue
    return false
  end
  return true
end

# Change task status. Possible URIs are: `
# - /task/Cancelled
# - /task/Completed: requires taskURI argument
# - /task/Running
# - /task/Error
# - /task/pid: requires pid argument
# IMPORTANT NOTE: Rack does not accept empty PUT requests. Please send an empty parameter (e.g. with -d '' for curl) or you will receive a "411 Length Required" error.
# @param [optional, String] resultURI URI of created resource, required for /task/Completed
# @param [optional, String] pid Task PID, required for /task/pid
# @param [optional, String] description Task description
# @param [optional, String] percentageCompleted progress value, can only be set while running
# @return [] nil
put '/:id/:hasStatus/?' do
  
	task = Task[params[:id]]
  raise OpenTox::NotFoundError.new"Task #{params[:id]} not found." unless task
	task.hasStatus = params[:hasStatus] unless /pid/ =~ params[:hasStatus]
  task.description = params[:description] if params[:description]
  # error report comes as yaml string
  task.error_report_yaml = params[:errorReport] if params[:errorReport]
  
	case params[:hasStatus]
	when "Completed"
		LOGGER.debug "Task " + params[:id].to_s + " completed"
    raise OpenTox::BadRequestError.new"no param resultURI when completing task" unless params[:resultURI]
    task.resultURI = params[:resultURI]
		task.finished_at = DateTime.now
    task.percentageCompleted = 100
    task.pid = nil
  when "pid"
    task.pid = params[:pid]
  when "Running"
    raise OpenTox::BadRequestError.new"Task cannot be set to running after not running anymore" if task.hasStatus!="Running"
    task.waiting_for = params[:waiting_for] if params.has_key?("waiting_for")
    if params.has_key?("percentageCompleted")
      task.percentageCompleted = params[:percentageCompleted].to_f
      #LOGGER.debug "Task " + params[:id].to_s + " set percentage completed to: "+params[:percentageCompleted].to_s
    end
	when /Cancelled|Error/
    if task.waiting_for and task.waiting_for.uri?
      Thread.new do # try cancelling the child task (in thread to avoid deadlocks) 
        begin
          w = OpenTox::Task.find(task.waiting_for)
          w.cancel if w.running?
        rescue
        end
      end
    end
    LOGGER.debug("Aborting task '"+task.uri.to_s+"' with pid: '"+task.pid.to_s+"'")
		Process.kill(9,task.pid.to_i) unless task.pid.nil?
		task.pid = nil
  else
     raise OpenTox::BadRequestError.new("Invalid value for hasStatus: '"+params[:hasStatus].to_s+"'")
  end
	
  raise"could not save task" unless task.save
end

# Delete a task
# @return [text/plain] Status message
delete '/:id/?' do
	task = Task[params[:id]]
  raise OpenTox::NotFoundError.new "Task #{params[:id]} not found." unless task
	begin
		Process.kill(9,task.pid) unless task.pid.nil?
    task.delete
    response['Content-Type'] = 'text/plain'
    "Task #{params[:id]} deleted."
	rescue
		raise"Cannot kill task with pid #{task.pid}"
	end
end

# Delete all tasks
# @return [text/plain] Status message
delete '/?' do
	Task.all.each do |task|
		begin
			Process.kill(9,task.pid.to_i) unless task.pid.nil?
      task.delete
      response['Content-Type'] = 'text/plain'
      "All tasks deleted."
		rescue
			"Cannot kill task with pid #{task.pid}"
		end
	end
end
