module OpenTox
  class Application < Service

    helpers do
      def status_code uri
        sparql = "SELECT ?o WHERE { GRAPH <#{uri}> { <#{uri}> <#{RDF::OT.hasStatus}> ?o. } }"
        status = Backend::FourStore.query(sparql,nil).last.gsub(/"|'/,'').gsub(/\^\^.*$/,'') 
        case status
        when "Completed"
          200
        when "Running"
          202
        when "Cancelled"
          503
        when "Error"
          sparql = "SELECT ?code WHERE { GRAPH <#{uri}> { <#{uri}> <#{RDF::OT.error}> ?error. ?error <#{RDF::OT.statusCode}> ?code } }"
          code = Backend::FourStore.query(sparql,nil).last.to_i
          code ? code : 500
        end
      end

    end

    get '/task/:id/?' do
      uri = uri("/task/#{params[:id]}")
      code = status_code(uri)
      if request.env['HTTP_ACCEPT'] == "text/uri-list" # return resultURI
        halt code, uri unless code == 200
        sparql = "SELECT ?o WHERE { GRAPH <#{uri}> { <#{uri}> <#{RDF::OT.resultURI}> ?o. } }"
        result_uri = Backend::FourStore.query(sparql,nil).last.gsub(/"|'/,'').gsub(/\^\^.*$/,'')
        halt code, result_uri
      else
        rdf = FourStore.get(uri, request.env['HTTP_ACCEPT'])
        halt code, rdf
      end
    end

    put '/task/:id/:status/?' do
      uri = uri("/task/#{params[:id]}")
      sparql = []
      case params[:status]
      when "Completed"
        bad_request_error "No resultURI parameter recieved. Cannot complete task '#{uri}' without resultURI." unless params[:resultURI]
        sparql << "DELETE DATA { GRAPH <#{uri}> {<#{uri}> <#{RDF::OT.hasStatus}> \"Running\"}}"
        sparql << "INSERT DATA { GRAPH <#{uri}> {<#{uri}> <#{RDF::OT.hasStatus}> \"Completed\"}}"
        sparql << "INSERT DATA { GRAPH <#{uri}> {<#{uri}> <#{RDF::OT.resultURI}> <#{params[:resultURI]}>}}"
        sparql << "INSERT DATA { GRAPH <#{uri}> {<#{uri}> <#{RDF::OT.percentageCompleted}> \"100.0\"}}"
        sparql << "INSERT DATA { GRAPH <#{uri}> {<#{uri}> <#{RDF::OT.finished_at}> \"#{DateTime.now}\"}}"
      when "Running"
        sparql << "INSERT DATA { GRAPH <#{uri}> {<#{uri}> <#{RDF::OT.percentageCompleted}> \"#{params["percentageCompleted"].to_f}\"^^#{RDF::XSD.float}}" if params["percentageCompleted"]
        #task.waiting_for = params[:waiting_for] if params.has_key?("waiting_for")
      when "Cancelled"
        sparql << "DELETE DATA { GRAPH <#{uri}> {<#{uri}> <#{RDF::OT.hasStatus}> \"Running\"}}"
        sparql << "INSERT DATA { GRAPH <#{uri}> {<#{uri}> <#{RDF::OT.hasStatus}> \"Cancelled\"}}"
        sparql << "INSERT DATA { GRAPH <#{uri}> {<#{uri}> <#{RDF::OT.finished_at}> \"#{DateTime.now}\"}}"
      when "Error"
        sparql << "DELETE DATA { GRAPH <#{uri}> {<#{uri}> <#{RDF::OT.hasStatus}> \"Running\"}}"
        sparql << "INSERT DATA { GRAPH <#{uri}> {<#{uri}> <#{RDF::OT.hasStatus}> \"Error\"}}"
        sparql << "INSERT DATA { GRAPH <#{uri}> {<#{uri}> <#{RDF::OT.finished_at}> \"#{DateTime.now}\"}}"
        id = params[:errorReport].split("\n").first.sub(/^(_:\w+) .*/,'\1')
        params[:errorReport] += "\n<#{uri}> <#{RDF::OT.error}> #{id} ."
        Backend::FourStore.post uri, params[:errorReport], "text/plain" if params[:errorReport]
        #if task.waiting_for and task.waiting_for.uri?
          # try cancelling the child task
      else
         bad_request_error "Invalid status value: '"+params[:status].to_s+"'"
      end
      sparql.each{|q| Backend::FourStore.update q}
    end

  end
end

