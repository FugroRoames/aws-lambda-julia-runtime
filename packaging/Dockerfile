ARG JL_VERSION_BASE=0.6
ARG JL_VERSION_PATCH=4
ARG JL_VERSION=$JL_VERSION_BASE.$JL_VERSION_PATCH

FROM octech/lambdajl:$JL_VERSION

ARG JL_VERSION
ARG JL_VERSION_BASE

ARG LAMBDA_MODULE

# For https://github.com/samoconnor/InfoZIP.jl
ENV HAVE_INFOZIP=1


# Install required Julia packages.
COPY REQUIRE /var/task/julia/v$JL_VERSION_BASE/
RUN julia -e 'Pkg.update(); Pkg.resolve()'

# Get latest AWSLambdaJuliaRuntime.jl module
COPY bundle/AWSLambdaJuliaRuntime.jl \
	/var/task/julia/v$JL_VERSION_BASE/AWSLambdaJuliaRuntime/src/

# Copying lambda function code
COPY bundle/$LAMBDA_MODULE/* \
	/var/task/julia/v$JL_VERSION_BASE/$LAMBDA_MODULE/src/



# Recompile sys.so with required packages.
RUN mkdir -p /tmp/julia/sys                                                 && \
	julia -e '                                                                 \
		open("/tmp/julia/userimg.jl", "w") do f;                               \
			println(f,"using AWSLambdaJuliaRuntime");                          \
			println(f,"using word_count");                                     \
			for p in eachline(joinpath(Pkg.dir(), "REQUIRE"))                  \
				println(f, "using $p")                                         \
			end                                                                \
		end'                                                                && \
	julia /var/task/share/julia/build_sysimg.jl                                \
			/tmp/julia/sys                                                     \
			core-avx-i                                                         \
			/tmp/julia/userimg.jl

RUN cp /tmp/julia/sys.so /var/task/lib/julia/                               && \
	rm /var/task/julia/lib/v$JL_VERSION_BASE/*.ji

# Remove unnecessary files.
RUN find julia -name '.git' \
	-o -name '.cache' \
	-o -name '.travis.yml' \
	-o -name '.gitignore' \
	-o -name 'REQUIRE' \
	-o -name 'LICENSE' \
	-o -name 'test' \
	-o -path '*/deps/usr/downloads' \
	-o -path '*/deps/usr/manifests' \
	-o -path '*/deps/downloads' \
	-o -path '*/deps/builds' \
	-o -path '*/deps/src' \
	-o -path '*/deps/usr/logs' \
	-o -path '*/JSON/data' \
	-o \( -type f -path '*/deps/src/*' ! -name '*.so.*' \) \
	-o \( -type f -path 'julia/*' -name '*.jl' \) \
	-o -path '*/deps/usr/include' \
	-o -path '*/deps/usr/bin' \
	-o -path '*/deps/usr/lib/*.a' \
	-o -name 'doc' \
	-o -name 'docs' \
	-o -name 'examples' \
	-o -name '*.md' \
	-o -name '*.yml' \
	-o -name '*.toml' \
	-o -name '*.tar.gz' \
	-o -name 'METADATA' \
	-o -name 'META_BRANCH' \
	| xargs rm -rf


# Install bootstrap
COPY bootstrap /var/task/bootstrap

# Start fresh with build container to bundle up the runtime
FROM lambci/lambda:build-python2.7

COPY --from=0 /var/task/ /var/task-build/

# Copy julia binary and libraries to /var/task-staging.
RUN mkdir -p /var/task/bin                                                  && \
	mkdir -p /var/task/lib/julia                                            && \
	mkdir -p /var/task/share/julia

# Copy everything we need to bundle into current dir
# maintain the proper folder structure (bin, lib, share)
RUN cp /var/task-build/bin/julia                bin/                        && \
	cp /usr/bin/zip                             bin/                        && \
	cp -a /var/task-build/lib/julia/*.so*       lib/julia/                  && \
	rm -f                                       lib/julia/*-debug.so*       && \
	cp -a /var/task-build/lib/*.so*             lib/                        && \
	rm -f                                       lib/*-debug.so*             && \
	cp -a /usr/lib64/libgfortran.so*            lib/                        && \
	cp -a /usr/lib64/libquadmath.so*            lib/                        && \
	cp -a /var/task-build/julia                 .                           && \
	cp -a /var/task-build/share/julia/cert.pem  share/julia/                && \
	cp /var/task-build/bootstrap                ./bootstrap


# FIXME Remove "|| true" When MbedTLS stripping fix is released.
# https://github.com/JuliaWeb/MbedTLS.jl/issues/140
RUN for f in $(find . -name '*.so'); do strip $f || true; done
