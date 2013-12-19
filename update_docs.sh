#!/bin/sh

cd ../origin-server/documentation && bundle exec rake package
cd ../../openshift.github.com/
cp -r ../origin-server/documentation/package/* .
git add .
exit
