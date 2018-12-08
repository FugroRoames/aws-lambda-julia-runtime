## AWS Lambda Julia Lang Runtime

Julia implementation of the lambda runtime API

Currently supporting Julia 0.6.X

## Building

Build the base Container where it install julia on AWS Lambda like environment

`make build-base`


Build the runtime and bundle-up (Zip) so that it can be deployed as a layer in AWS lambda.

`make build-runtime`

bundle will be in `packaging` directory



## TODO

- Automated testing. Possibly by running in lambda Docker.
- Implement proper way to use the runtime in client project.
- Add few more examples.
- List in JuliaLang MetaData repository.
- Support Julia 1.x.
- Share JuliaRuntime as a layer in AWS Lambda so others can use it without building from scratch.
