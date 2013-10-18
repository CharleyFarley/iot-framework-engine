%% @author Tommy Mattsson, Georgios Koutsoumpakis
%%   [www.csproj13.student.it.uu.se]
%% @version 1.0
%% @copyright [Copyright information]
%%
%% @doc == suggest ==
%% 
%%  
%%
%% @end
-module(suggest).
-export([init/1, allowed_methods/2, process_post/2, content_types_provided/2, 
		 get_suggestion/2]).


-include_lib("erlastic_search.hrl").
-include("webmachine.hrl").


-define(INDEX, "sensorcloud").

%% @doc
%% Function: init/1
%% Purpose: init function used to fetch path information from webmachine dispatcher.
%% Returns: {ok, undefined}
%% @end
-spec init([]) -> {ok, undefined}.
init([]) -> 
    {ok, undefined}.

%% @doc
%% Function: allowed_methods/2
%% Purpose: Used to define what methods are allowed one the given URI's.
%% Returns: {List, ReqData, State}, where list is the allowed methods for the given URI. 
%% @end
-spec allowed_methods(ReqData::term(),State::term()) -> {list(), term(), term()}.

allowed_methods(ReqData, State) ->
	%erlang:display(ReqData),
	%erlang:display(parse_path(wrq:path(ReqData))),
	case parse_path(wrq:path(ReqData)) of
		[{"suggest", _Term}] ->
			{['GET'], ReqData, State}; 
		[{"suggest"}] ->
			{['POST'], ReqData, State}; 
		[error] ->
		    {[], ReqData, State} 
	end.



%% @doc
%% Function: content_types_provided/2
%% Purpose: based on the Accept header on a 'GET' request, we provide different media types to the client.
%% A code 406 is returned to the client if we cannot return the media-type that the user has requested.
%% Returns: {[{Mediatype, Handler}], ReqData, State}
%% @end
-spec content_types_provided(ReqData::term(),State::term()) -> {list(), term(), term()}.

content_types_provided(ReqData, State) ->
	{[{"application/json", get_suggestion}], ReqData, State}.


%% @doc
%% Function: process_post/2
%% Purpose: Used to handle POST requests by creating streams, or search for streams in elastic search
%% Returns: {Success, ReqData, State}, where Success is true if the post request is
%% successful and false otherwise.
%% @end
-spec process_post(ReqData::term(),State::term()) -> {boolean(), term(), term()}.

process_post(ReqData, State) ->
	erlang:display("suggestion works?"),
	{Query,_,_} = json_handler(ReqData, State),	
	case erlastic_search:suggest(?INDEX, Query) of	
		{error, Reason} -> {false, wrq:set_resp_body(json_encode(Reason),ReqData), State};
		{ok,List} -> {true, wrq:set_resp_body(json_encode(List),ReqData), State}
	end.



%% @doc
%% Function: get_suggestion/2
%% Purpose: Used to handle GET requests for suggestions by giving the term 
%% (model)
%% Returns: {String, ReqData, State}
%% @end
-spec get_suggestion(ReqData::term(),State::term()) -> {boolean(), term(), term()}.

get_suggestion(ReqData, State) ->
	erlang:display("get suggestion"),
	case proplists:get_value('term', wrq:path_info(ReqData)) of
		undefined ->
			{{halt, 400}, ReqData, State};
		Term ->
			%forms the query
			Query = "{                   
    					\"test-suggest\" : {     
        					\"text\" : \""++Term++"\",
        					\"completion\" : {                    
            					\"field\" : \"suggest\",
								\"size\" : 1            
        					}                                                   
    					}                                      
					}",
			case erlastic_search:suggest(?INDEX, Query) of	
				{error, Reason} -> {json_encode(Reason),ReqData, State};
				{ok,List} -> 
					erlang:display("---->"),
					EncodedList = json_encode(List),
					case re:run(EncodedList, "\"options\":\\[\\]", [{capture, first, list}]) of
						{match, _} -> 
							{{halt,404},ReqData, State};
						_->
							{json_encode(List),ReqData, State}
					end
			end
	end.


%% @doc
%% Function: make_to_string/1
%% Purpose: Used to convert JSON with binary data left to string
%% Returns: Returns the string represented by the given list
%% @end

make_to_string([]) ->
	[];
make_to_string([First|Rest]) ->
	case is_list(First) of
		true -> make_to_string(First) ++ make_to_string(Rest);
		false ->
			case is_binary(First) of
				true -> binary:bin_to_list(First) ++ make_to_string(Rest);
				false -> [First] ++ make_to_string(Rest)
			end
	end.
%% @doc
%% Function: remove_search_part/3
%% Purpose: Used to remove the search header of a search JSON 
%% Returns: Returns the list of JSON objects return from the search
%% @end
-spec remove_search_part(JSONString::string(),FoundLeft::boolean(),OpenBrackets::integer()) -> string().

remove_search_part([],_,_) ->
	[];
remove_search_part([First|Rest],true,1) ->
	case First of
		$] ->
			[First];
		$[ ->
			[First|remove_search_part(Rest,true,2)];
		_ ->
			[First|remove_search_part(Rest,true,1)]
	end;
remove_search_part([First|Rest],true,Val) ->
  	case First of
		$] ->
			[First|remove_search_part(Rest,true,Val-1)];
		$[ ->
			[First|remove_search_part(Rest,true,Val+1)];
		_ ->
			[First|remove_search_part(Rest,true,Val)]
	end;
remove_search_part([First|Rest],false,Val) ->
	case First of
		$[ ->
			[First|remove_search_part(Rest,true,1)];
		_ ->
			remove_search_part(Rest,false,Val)
	end.

%% @doc
%% Function: is_search/1
%% Purpose: Used to deiced if the URI specify a search
%% Returns: True if URI specify a search, false otherwise
%% @end
-spec is_search(ReqData::term()) -> boolean().

is_search(ReqData) ->
	URIList = string:tokens(wrq:path(ReqData), "/"),
	IsSearch = (string:sub_string(lists:nth(length(URIList),URIList),1,7) == "_search").

%% @doc
%% Function: json_handler/2
%% Purpose: Used to get the json object from the request
%% Returns: {Json,ReqData,State}
%% @end
-spec json_handler(ReqData::term(),State::term()) -> {boolean(), term(), term()}.

json_handler(ReqData, State) ->
	[{Value,_ }] = mochiweb_util:parse_qs(wrq:req_body(ReqData)), 
	{Value, ReqData, State}.

%% @doc
%% Function: create_update/1
%% Purpose: Used to create the update document sent to erlastic search
%% Returns: The update document to send to erlasticsearch
%% @end
-spec create_update(Stream::string()) -> string().

create_update(Stream) ->
	"{\n\"doc\" : " ++ Stream ++ "\n}".

%% @doc
%% Function: add_field/3
%% Purpose: Used to add a new field to the given string representation of
%%          of a JSON object, the field will be FieldName : FieldValue
%% Returns: The string representation of the JSON object with the new field
%% @end
-spec add_field(Stream::string(),FieldName::string(),FieldValue::term()) -> string().

add_field(Stream,FieldName,FieldValue) ->
	case is_integer(FieldValue) of
		true ->
			string:substr(Stream,1,length(Stream)-1) ++ ",\n\"" ++ FieldName ++ "\" : " ++ FieldValue ++ "\n}";
		false ->
			string:substr(Stream,1,length(Stream)-1) ++ ",\n\"" ++ FieldName ++ "\" : \"" ++ FieldValue ++ "\"\n}"
	end.
			

%% @doc
%% Function: parse_path/1
%% Purpose: Used to parse the URI path
%% Returns: The parsed URI path as a list
%% @end
-spec parse_path(Path::file:name_all()) -> list().

parse_path(Path) -> 
	[_|T] = filename:split(Path),
	pair(T).

%% @doc
%% Function: pair/1
%% Purpose: Used to create a new list of tuples where each 
%%          2 elements are paired
%% Returns: The paired list
%% @end
-spec pair(PathList::list()) -> list().

pair([]) -> [];
pair([A]) -> [{A}];
pair([A,B|T]) ->
	[{A,B}|pair(T)].

%% @doc
%% Function: transform/2
%% Purpose: Used to create the query for search, expects more fields
%% if AddAnd euqal to true
%% Returns: The query string from given from the list
%% were the list will be {Field,Value} tuples
%% @end
-spec transform(QueryList::list(),AddAnd::boolean()) -> list().

transform([],true) -> "&";
transform([],false) -> "";
transform([{Field,Value}|Rest],AddAnd) ->
	case Rest of 
		[] -> Field ++ ":" ++ Value ++ transform(Rest,AddAnd);
		_ -> Field ++ ":" ++ Value ++ "&" ++ transform(Rest,AddAnd)
	end.

%% @doc
%% Function: json_encode/1
%% Purpose: Used to transform the given data to json
%% Returns: JSON that is created
%% @end

% Taken from erlasticsearch
json_encode(Data) ->
    (mochijson2:encoder([{utf8, true}]))(Data).

%% @doc
%% Function: update_doc/4
%% Purpose: Used to update document in elastic search
%% Returns: JSON response from elastic search server
%% @end

% Taken from erlasticsearch and modified to not encode
update_doc(Index, Type, Id, Mochijson) ->
    update_doc(Index, Type, Id, Mochijson, []).

%% @doc
%% Function: update_doc/5
%% Purpose: Used to update document in elastic search
%% Returns: JSON response from elastic search server
%% @end

% Taken from erlasticsearch and modified to not encode
update_doc(Index, Type, Id, Json, Qs) ->
    Id1 = mochiweb_util:quote_plus(Id),
    ReqPath = Index ++ [$/ | Type] ++ [$/ | Id1] ++ "/_update",
    erls_resource:post(#erls_params{}, ReqPath, [], Qs, Json, []).


add_suggestion(Resource, Json) ->
	ResourceId = binary_to_list(proplists:get_value(<<"_id">>, Json)),
	erlang:display(ResourceId),
	Manufacturer = lib_json:get_value_field(Resource, "manufacturer"),
	Tags = lib_json:get_value_field(Resource, "tags"),
	Polling_freq = lib_json:get_value_field(Resource, "polling_freq"),
	Weight = scoring:calc(Resource, resource),
	Suggestion = "{
		\"resource_id\" : \"" ++ ResourceId++ "\",
		\"suggest\" : {
			\"input\" : [ \"smartphone\" ], 
			\"output\" : \"" ++ get_timestamp() ++ "\",
			\"payload\" : { 
				\"manufacturer\" : \"" ++ Manufacturer ++ "\",
				\"tags\" : \"" ++ Tags ++ "\",
				\"polling_freq\" : \"" ++ Polling_freq ++ "\"
			},
			\"weight\" : " ++ integer_to_list(Weight) ++ "
		}				
	}",
	case erlastic_search:index_doc(?INDEX, "suggestion", Suggestion) of 
		{error, S} -> erlang:display("Suggestion not saved ");
		{ok, _} -> 	erlang:display("Suggestion added :D")
	end.


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Should be moved to own module later
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

get_timestamp() ->
    TS = {MSec,Sec,Micro} = os:timestamp(),
	{{Year,Month,Day},{Hour,Minute,Second}} = calendar:now_to_universal_time(TS),
    Mstr = element(Month,{"Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"}),
    io_lib:format("~2w ~s ~4w ~2w:~2..0w:~2..0w.~6..0w", [Day,Mstr,Year,Hour,Minute,Second,Micro]).




