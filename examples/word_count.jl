# Example julia lambda function
# Couting words in a file in S3 path

# See following resources for S3 in julia
# - https://juliacloud.github.io/AWSCore.jl/build/AWSS3.html
# - https://github.com/JuliaCloud/AWSS3.jl

module word_count

using AWSLambdaJuliaRuntime
using AWSS3
using AWSCore

#= The handler function =#
function handler(event_data::InvocationRequest)
	# download some file from S3 path
	# count number of unique words
	# put result back to S3 path or send in response

	println("Hello World : $(event_data.payload)")
	run(`ls`)

	i_am_good = true
	if i_am_good
		return success_invocation_response("""{"msg": "Me Rockz!"}""", "application/json")
	else
		return failure_invocation_response("Me Suckz!", "some_error_type")
	end
end

end # module word_count
