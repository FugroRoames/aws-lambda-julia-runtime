## AWS Lambda Runtime for Julia Lang
## 2018 (C) Fugro ROAMES <marines@roames.com.au>


# AWS Lambda Runtime Interface - https://docs.aws.amazon.com/lambda/latest/dg/runtimes-api.html
# AWS Lambda Custom Runtimes   - https://docs.aws.amazon.com/lambda/latest/dg/runtimes-custom.html
# AWS Lambda Runtime ENV Vars  - https://docs.aws.amazon.com/lambda/latest/dg/current-supported-versions.html


__precompile__()

module AWSLambdaJuliaRuntime

using HTTP
using JSON
using MicroLogging

export success_invocation_response,
       failure_invocation_response,
       InvocationRequest,
       InvocationResponse

global AWS_LAMBDA_RUNTIME_API_INIT_ENDPOINT = ""
global AWS_LAMBDA_RUNTIME_API_NEXT_ENDPOINT = ""
global AWS_LAMBDA_RUNTIME_API_RESULTS_ENDPOINT = ""

const REQUEST_ID_HEADER = "Lambda-Runtime-Aws-Request-Id"
const TRACE_ID_HEADER = "Lambda-Runtime-Trace-Id"
const CLIENT_CONTEXT_HEADER = "Lambda-Runtime-Client-Context"
const COGNITO_IDENTITY_HEADER = "Lambda-Runtime-Cognito-Identity"
const DEADLINE_MS_HEADER = "Lambda-Runtime-Deadline-Ms"
const FUNCTION_ARN_HEADER = "Lambda-Runtime-Invoked-Function-Arn"

# InvocationRequest represent Lambda invocation request data
mutable struct InvocationRequest
    # The user's payload represented as a UTF-8 string.
    payload::String

    # An identifier unique to the current invocation.
    request_id::String

    # X-Ray tracing ID of the current invocation.
    xray_trace_id::String

    # Information about the client application and device when invoked through the AWS Mobile SDK.
    client_context::String

    # Information about the Amazon Cognito identity provider when invoked through the AWS Mobile SDK.
    cognito_identity::String

    # The ARN requested. This can be different in each invoke that executes the same version.
    function_arn::String

    # Function execution deadline counted in milliseconds since the Unix epoch.
    deadline::UInt64

    function InvocationRequest()
        return new("", "", "", "", "", "", 0)
    end
end

# The number of milliseconds left before lambda terminates the current execution.
function get_time_remaining(req::InvocationRequest)
    return (time() / 1000) - req.deadline
end

mutable struct InvocationResponse
     # The output of the function which is sent to the lambda caller.
    payload::String

     # The MIME type of the payload.
    content_type::String

     # Flag to distinguish if the contents are for successful or unsuccessful invocations.
    success::Bool

    function InvocationResponse(payload::String, content_type::String, success::Bool)
        new(payload, content_type, success)
    end
end

function success_invocation_response(payload::String, content_type::String="text/html")
    return InvocationResponse(payload, content_type, true)
end

function failure_invocation_response(err_msg::String, err_type::String)
    payload = Dict(
        "errorMessage"=>err_msg,
        "errorType"=>err_type,
        "stackTrace"=>Vector{String, 1}(0)
    )
    return InvocationResponse(
        JSON.json(payload),
        "application/json",
        false
    )
end

function http_resp_success(http_code::Integer)
    return ((http_code >= 200) && (http_code <= 299))
end

function initialise()
    global AWS_LAMBDA_RUNTIME_API_INIT_ENDPOINT
    global AWS_LAMBDA_RUNTIME_API_NEXT_ENDPOINT
    global AWS_LAMBDA_RUNTIME_API_RESULTS_ENDPOINT

    LOG_LEVEL = get(ENV, "JULIA_RUNTIME_LOG_LEVEL", "error")
    configure_logging(AWSLambdaJuliaRuntime, min_level=parse(LOG_LEVEL))

    @info "[AWSLambdaJuliaRuntime] Initialising..."

    AWS_LAMBDA_RUNTIME_API = get(ENV, "AWS_LAMBDA_RUNTIME_API", nothing)
    if AWS_LAMBDA_RUNTIME_API == nothing
        # TODO: send init error
        @error "[AWSLambdaJuliaRuntime] AWS_LAMBDA_RUNTIME_API not defined!"
        error("[AWSLambdaJuliaRuntime] AWS_LAMBDA_RUNTIME_API not defined!")
    end
    AWS_LAMBDA_RUNTIME_API_INIT_ENDPOINT = "http://$(AWS_LAMBDA_RUNTIME_API)/2018-06-01/runtime/init/error"
    AWS_LAMBDA_RUNTIME_API_NEXT_ENDPOINT = "http://$(AWS_LAMBDA_RUNTIME_API)/2018-06-01/runtime/invocation/next"
    AWS_LAMBDA_RUNTIME_API_RESULTS_ENDPOINT = "http://$(AWS_LAMBDA_RUNTIME_API)/2018-06-01/runtime/invocation/"

    @info "[AWSLambdaJuliaRuntime] Initialised"
end

function get_next_event()
    resp = HTTP.request("GET", AWS_LAMBDA_RUNTIME_API_NEXT_ENDPOINT; readtimeout=5, retry=true, retries=2)
    @debug "[AWSLambdaJuliaRuntime] get_next_event : event=" resp
    if !http_resp_success(resp.status)
        # error
        return resp.status, nothing
    end

    invoc_req = InvocationRequest()

    # parse request body
    invoc_req.payload = String(resp.body)

    # process request HTTP header
    for (k,v) in resp.headers
        if k == REQUEST_ID_HEADER
            invoc_req.request_id = String(v)
        end
        if k == TRACE_ID_HEADER
            invoc_req.xray_trace_id = String(v)
        end
        if k == CLIENT_CONTEXT_HEADER
            invoc_req.client_context = String(v)
        end
        if k == COGNITO_IDENTITY_HEADER
            invoc_req.cognito_identity = String(v)
        end
        if k == FUNCTION_ARN_HEADER
            invoc_req.function_arn = String(v)
        end
        if k == DEADLINE_MS_HEADER
            ms = parse(UInt64, String(v))
            invoc_req.deadline = ms * 1000 # deadline in mu sec
        end
    end

    @debug "[AWSLambdaJuliaRuntime] Received event: " invoc_req

    if invoc_req.request_id == nothing
        return -1, invoc_req
    end

    return resp.status, invoc_req
end

# Send back the result of lambda invocation (success or failure)
function post_handler_response(handler_resp::InvocationResponse, invoc_req::InvocationRequest)
    @debug "[AWSLambdaJuliaRuntime] post_handler_response handler_resp=" handler_resp

    url = ""
    if handler_resp.success
        url = "$(AWS_LAMBDA_RUNTIME_API_RESULTS_ENDPOINT)$(invoc_req.request_id)/response"
    else
        url = "$(AWS_LAMBDA_RUNTIME_API_RESULTS_ENDPOINT)$(invoc_req.request_id)/error"
    end

    headers = Vector{Pair{String, String}}()
    push!(headers, Pair("content-type", handler_resp.content_type))
    push!(headers, Pair("content-length", string(length(handler_resp.payload))))

    @debug "[AWSLambdaJuliaRuntime] Posting response url=$(url) headers=$(headers) payload=$(handler_resp.payload)"
    resp = HTTP.request("POST", url, headers, handler_resp.payload)

    if !http_resp_success(resp.status)
        @error "[AWSLambdaJuliaRuntime] Post response failed. error=$(resp.status) resp=$(resp.body)"
        return
    end

    return
end

"""
main entry point to the module
This gets called by the `bootstrap` script
"""
# function main(lambda_module::Module, handler_name::String="handler")
function main(lambda_module::Module)
    # Initialise runtime
    initialise()

    retries = 0
    max_retries = 3
    invoc_req = nothing

    # In (infinite) loop, process Lambda invocations
    while retries < max_retries
        ## Get an event
        # invoc_req=$(curl -sS -LD "$HEADERS" -X GET "http://${AWS_LAMBDA_RUNTIME_API}/2018-06-01/runtime/invocation/next")
        # REQUEST_ID=$(grep -Fi Lambda-Runtime-Aws-Request-Id "$HEADERS" | tr -d '[:space:]' | cut -d: -f2)
        resp_status, invoc_req = get_next_event()
        if !http_resp_success(resp_status)
            @error "[AWSLambdaJuliaRuntime] get_next_event failed: code=$(resp_status) req=" invoc_req
            retries += 1
            continue
        end

        retries = 0

        ## Call handler function in the client module
        handler_resp = lambda_module.handler(invoc_req)
        ## handler_resp = eval(parse("lambda_module.$(handler_name)(invoc_req)"))

        ## Send the response
        # curl -X POST "http://${AWS_LAMBDA_RUNTIME_API}/2018-06-01/runtime/invocation/$REQUEST_ID/response"  -d "$RESPONSE"
        post_handler_response(handler_resp, invoc_req)
    end

    if retries == max_retries
        @error "[AWSLambdaJuliaRuntime] Exhausted all retries ($(retries)/$(max_retries)). Exiting!"
    end
end

precompile(main, (Module,))
precompile(post_handler_response, (InvocationResponse, InvocationRequest))
precompile(get_next_event, ())
precompile(initialise, ())
precompile(success_invocation_response, (String, String))
precompile(failure_invocation_response, (String, String))
precompile(get_time_remaining, (InvocationRequest,))
precompile(http_resp_success, (Integer,))

end # module AWSLambdaJuliaRuntime
