#!/bin/bash -e
BUILD=$1
if [ -z "$BUILD" ]; then
    exit 1
fi

docker pull python:3.9-alpine
if [[ ${BUILD} != *"b"* ]]; then
    docker build -f Dockerfile-3.9-alpine --build-arg BUILD=$BUILD . \
                 -t oitacr.azurecr.io/pmartin47/salt:3.9-latest-alpine \
                 -t oitacr.azurecr.io/pmartin47/salt:3.9-$BUILD-alpine \
                 -t oitacr.azurecr.io/pmartin47/salt:3.9-latest \
                 -t oitacr.azurecr.io/pmartin47/salt:3.9-$BUILD
else
    docker build -f Dockerfile-3.9-alpine --build-arg BUILD=$BUILD . \
                 -t oitacr.azurecr.io/pmartin47/salt:3.9-$BUILD-alpine \
                 -t oitacr.azurecr.io/pmartin47/salt:3.9-$BUILD
fi

docker pull python:3.10-alpine
if [[ ${BUILD} != *"b"* ]]; then
	docker build -f Dockerfile-3.10-alpine --build-arg BUILD=$BUILD . \
        	     -t oitacr.azurecr.io/pmartin47/salt:3.10-latest-alpine \
	             -t oitacr.azurecr.io/pmartin47/salt:3.10-$BUILD-alpine \
        	     -t oitacr.azurecr.io/pmartin47/salt:latest-alpine \
	             -t oitacr.azurecr.io/pmartin47/salt:$BUILD-alpine \
        	     -t oitacr.azurecr.io/pmartin47/salt:3.10-latest \
	             -t oitacr.azurecr.io/pmartin47/salt:3.10-$BUILD \
        	     -t oitacr.azurecr.io/pmartin47/salt:latest \
	             -t oitacr.azurecr.io/pmartin47/salt:$BUILD
else
	docker build -f Dockerfile-3.10-alpine --build-arg BUILD=$BUILD . \
                     -t oitacr.azurecr.io/pmartin47/salt:3.10-$BUILD-alpine \
                     -t oitacr.azurecr.io/pmartin47/salt:$BUILD-alpine \
                     -t oitacr.azurecr.io/pmartin47/salt:3.10-$BUILD \
                     -t oitacr.azurecr.io/pmartin47/salt:$BUILD
fi

#docker pull python:3.11-rc-alpine
#docker build -f Dockerfile-3.11-alpine . \
#             -t oitacr.azurecr.io/pmartin47/salt:3.11-latest-alpine \
#             -t oitacr.azurecr.io/pmartin47/salt:3.11-$BUILD-alpine \
#             -t oitacr.azurecr.io/pmartin47/salt:3.11-latest \
#             -t oitacr.azurecr.io/pmartin47/salt:3.11-$BUILD


az acr login -n oitacr
docker images | awk "/$BUILD/ { print \$1\":\"\$2 }" | xargs -I {} docker push {}
if [[ ${BUILD} != *"b"* ]]; then
	docker images | awk "/pmartin47\/salt/&&/latest/ { print \$1\":\"\$2 }" | xargs -I {} docker push {}
	docker images | awk "/pmartin47\/salt/&&/3.9-latest/ { print \$1\":\"\$2 }" | xargs -I {} docker push {}
	docker images | awk "/pmartin47\/salt/&&/3.10-latest/ { print \$1\":\"\$2 }" | xargs -I {} docker push {}
fi
