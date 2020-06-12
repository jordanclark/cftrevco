component {
	// cfprocessingdirective( preserveCase=true );

	function init(
		required string apiEmail
	,	required string apiPassword
	,	string authToken= ""
	,	string customerID= ""
	,	required string apiUrl= "https://b2bapi.trevcoinc.com/api/v1"
	) {
		this.apiEmail = arguments.apiEmail;
		this.apiPassword = arguments.apiPassword;
		this.apiUrl = arguments.apiUrl;
		this.customerID = arguments.customerID;
		this.authToken = arguments.authToken;
		this.authExpires = now();
		this.httpTimeOut = 120;
		return this;
	}

	function debugLog( required input ) {
		if ( structKeyExists( request, "log" ) && isCustomFunction( request.log ) ) {
			if ( isSimpleValue( arguments.input ) ) {
				request.log( "trevco: " & arguments.input );
			} else {
				request.log( "trevco: (complex type)" );
				request.log( arguments.input );
			}
		} else {
			var info= ( isSimpleValue( arguments.input ) ? arguments.input : serializeJson( arguments.input ) );
			cftrace(
				var= "info"
			,	category= "trevco"
			,	type= "information"
			);
		}
		return;
	}

	function getAuthToken() {
		var out= this.apiRequest( api= "POST /login", argumentCollection= {
			"email"= this.apiEmail
		,	"password"= this.apiPassword
		} );
		if ( out.success && structKeyExists( out.response, "token" ) && len( out.response.token ) ) {
			this.authToken = out.response.token;
			this.authExpires = parseDateTime( out.response.expirationDate );
			// this.customerID = out.response.customers[ 1 ].customerID;
		}
		return out;
	}

	boolean function isAuthenticated() {
		if( dateCompare( this.authExpires, now() ) != 1 ) {
			// auth equal or greater then now
			this.authToken = "";
		}
		if( !len( this.authToken ) ) {
			return false;
		}
		return true;
	}

	function getAuthenticated() {
		if( dateCompare( this.authExpires, now() ) != 1 ) {
			// auth equal or greater then now
			this.authToken = "";
		}
		if( !len( this.authToken ) ) {
			auth = this.getAuthToken();
			if( !auth.success ) { 
				return auth;
			}
		}
		return nullValue();
	}

	function whoAmI() {
		return this.getAuthenticated() ?: this.apiRequest( api= "GET /whoami" );
	}

	function listItems( numeric page= 1, numeric itemsPerPage= 100, boolean active, string sort= "", string order= "", string designName= "", string sku= "" ) {
		return this.getAuthenticated() ?: this.apiRequest( api= "GET /item", argumentCollection= arguments );
	}

	function listCategories( numeric page= 1, numeric itemsPerPage= 100, string sort= "", string order= "" ) {
		return this.getAuthenticated() ?: this.apiRequest( api= "GET /category", argumentCollection= arguments );
	}

	function listDesigns( numeric page= 1, numeric itemsPerPage= 100, string sort= "", string order= "", string q= "", string designId= "", string designName= "", string name= "" ) {
		return this.getAuthenticated() ?: this.apiRequest( api= "GET /design", argumentCollection= arguments );
	}

	function listStyles( numeric page= 1, numeric itemsPerPage= 100, string sort= "", string order= "" ) {
		return this.getAuthenticated() ?: this.apiRequest( api= "GET /itemStyle", argumentCollection= arguments );
	}

	struct function apiRequest( required string api ) {
		var http = {};
		var dataKeys = 0;
		var item = "";
		var out = {
			success = false
		,	args = arguments
		,	error = ""
		,	status = ""
		,	json = ""
		,	statusCode = 0
		,	response = ""
		,	verb = listFirst( arguments.api, " " )
		,	requestUrl = this.apiUrl & listRest( arguments.api, " " )
		,	headers = {}
		};
		structDelete( out.args, "api" );
		if ( out.verb == "GET" ) {
			out.requestUrl &= this.structToQueryString( out.args, true );
		} else if ( !structIsEmpty( out.args ) ) {
			out.body = serializeJSON( out.args, false, false );
		}
		this.debugLog( "API: #uCase( out.verb )#: #out.requestUrl#" );
		if ( structKeyExists( out, "body" ) ) {
			this.debugLog( out.body );
		}
		if ( structKeyExists( out, "body" ) ) {
			out.headers[ "Accept" ] = "application/json";
			out.headers[ "Content-Type" ] = "application/json";
		}
		if ( len( this.authToken ) ) {
			out.headers[ "Authorization" ] = "Bearer #this.authToken#";
		}
		if ( len( this.customerID ) ) {
			out.headers[ "customerId" ] = this.customerID;
		}
		if ( request.debug && request.dump ) {
			this.debugLog( out );
		}
		cftimer( type="debug", label="trevco request" ) {
			cfhttp( result="http", method=out.verb, url=out.requestUrl, charset="UTF-8", throwOnError=false, timeOut=this.httpTimeOut ) {
				if ( structKeyExists( out, "body" ) ) {
					cfhttpparam( type="body", value=out.body );
				}
				for ( item in out.headers ) {
					cfhttpparam( name=item, type="header", value=out.headers[ item ] );
				}
			}
		}
		// this.debugLog( http );
		out.response = toString( http.fileContent );
		//this.debugLog( out.response );
		out.statusCode = http.responseHeader.Status_Code ?: 500;
		if ( left( out.statusCode, 1 ) == 4 || left( out.statusCode, 1 ) == 5 ) {
			out.success = false;
			out.error = "status code error: #out.statusCode#";
		} else if ( out.response == "Connection Timeout" || out.response == "Connection Failure" ) {
			out.error = out.response;
		} else if ( left( out.statusCode, 1 ) == 2 ) {
			out.success = true;
		}
		// parse response 
		if ( len( out.response ) && isJson( out.response ) ) {
			try {
				out.response = deserializeJSON( out.response );
				if ( isStruct( out.response ) && structKeyExists( out.response, "meta" ) && structKeyExists( out.response.meta, "message" ) ) {
					out.success = false;
					out.error = out.response.meta.message;
				}
			} catch (any cfcatch) {
				out.error= "JSON Error: " & (cfcatch.message?:"No catch message") & " " & (cfcatch.detail?:"No catch detail");
			}
		} else {
			out.error= "Response not JSON: #out.response#";
		}
		if ( len( out.error ) ) {
			out.success = false;
		}
		this.debugLog( out.statusCode & " " & out.error );
		return out;
	}

	string function structToQueryString( required struct stInput, boolean bEncode= true ) {
		var sOutput = "";
		var sItem = "";
		var sValue = "";
		var amp = "?";
		for ( sItem in stInput ) {
			if ( structKeyExists( stInput, sItem ) ) {
				try {
					sValue = stInput[ sItem ];
					if ( len( sValue ) ) {
						if ( bEncode ) {
							sOutput &= amp & sItem & "=" & urlEncodedFormat( sValue );
						} else {
							sOutput &= amp & sItem & "=" & sValue;
						}
						amp = "&";
					}
				} catch (any cfcatch) {
				}
			}
		}
		return sOutput;
	}

}
