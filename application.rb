module OpenTox
  class Application < Service

    helpers do

      def status_code uri
        status = $mongo[SERVICE].find({:uri => uri}).distinct(:hasStatus).first
        case status
        when "Completed"
          200
        when "Running"
          202
        when "Cancelled"
          503
        when "Error"
          code = $mongo[SERVICE].find({:uri => uri}).distinct(:errorReport).first["statusCode"]
          code != "" ? code.to_i : 500
        else
          500
        end
      end

    end

    get '/task/:id/?' do
      uri = uri("/task/#{params[:id]}")
      code = status_code(uri)
      if @accept == "text/uri-list" # return resultURI
        halt code, uri unless code == 200
        halt code, $mongo[SERVICE].find({:uri => uri}).distinct(:resultURI).first
      else
        halt code, render($mongo[SERVICE].find({:uri => uri}).first)
      end
    end

    put '/task/:id/:status/?' do
      uri = uri("/task/#{params[:id]}")
      metadata = { :hasStatus => params[:status] }
      case params[:status]
      when "Completed"
        bad_request_error "No resultURI parameter recieved. Cannot complete task '#{uri}' without resultURI." unless params[:resultURI]
        metadata.merge!({
          :percentageCompleted => 100.0,
          :finished_at => DateTime.now.to_s
        })
      when "Running"
        metadata.merge!({ :percentageCompleted => params["percentageCompleted"].to_f}) if params["percentageCompleted"]
        #task.waiting_for = params[:waiting_for] if params.has_key?("waiting_for")
      when "Cancelled"
        metadata.merge!({ :finished_at => DateTime.now.to_s })
      when "Error"
        metadata.merge!({ :finished_at => DateTime.now.to_s, })
        metadata.merge!({ :errorReport => JSON.parse(params[:errorReport]) }) if params[:errorReport]
        #if task.waiting_for and task.waiting_for.uri?
          # try cancelling the child task
      else
         bad_request_error "Invalid status value: '"+params[:status].to_s+"'"
      end
      render  $mongo[SERVICE].find(:uri => uri).find_one_and_replace('$set' => metadata)
    end
    
    delete '/task/:id/?' do
      uri = uri("/task/#{params[:id]}")
      created_at = $mongo[SERVICE].find(:uri => uri).distinct(:created_at).first
      created = DateTime.parse(created_at)
      today = DateTime.now
      daysback = (today - 30)
      (created <= daysback) ? render($mongo[SERVICE].find(:uri => uri).find_one_and_delete)  : bad_request_error("Cannot delete tasks younger than 30 days.")
      # prevent backend type and version displayed
      result.split("\n").first
    end

  end
end

