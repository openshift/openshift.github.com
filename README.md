# openshift.github.io

This repo contains the static content of the [openshift.github.io](http://openshift.github.io/) site. This site is the current "home base" for OpenShift Origin, containing information on how to contribute, and serving the Origin [documentation](http://openshift.github.io/documentation/).

## Updating the Docs

The documentation source lives in the [origin-server](https://github.com/openshift/origin-server/tree/master/documentation) repository. The `update_docs.sh` utility in this repo is used to trigger the rendering of those documents and then to collect them under the `documentation` and `documentation-latest` directories in this repo. To perform this build process, do the following:

1. In a working directory, clone these three repos:
    * [origin-server](https://github.com/openshift/origin-server)
    * [openshift-pep](https://github.com/openshift/openshift-pep)
    * [openshift.github.com](https://github.com/openshift/openshift.github.com)

2. In the `origin-server` repo directory, you will need to create a tracking branch for the most recent Origin release:

    `git checkout --track <upstream|origin>/<origin-release-branch>`

    _upstream_ or _origin_ depends entirely upon how you initially set up the clone.  
    _origin-release-branch_ is currently `openshift-origin-release-3`

    **NOTE**: When Origin moves to the next release, you will need to modify the `package` task in the [documentation Rakefile](https://github.com/openshift/origin-server/blob/master/documentation/Rakefile) to use the new release branch name.
3. In the `openshift.github.com` directiory, create a working branch for your updates:

    `git checkout -b doc_updates`

4. Next, make sure you have the necessary Ruby gems. In the origin-server/documentation directory, run:

    `bundle install`

    **NOTE**: You must be using Ruby 1.9.3 or later to build the docs
5. Finally, you can run the docs update utility.
    * `cd` to the openshift.github.com repo directory
    * `./update_docs.sh`

    You may see warnings from AsciiDoctor as the docs are generated; this is normal.

6. Once the process is complete, a `git status` should reveal that the files under documentation and documentation-latest have all been updated. At a minumum, you will see a new render time date stamp in each file. Look for any new html files and `git add` them to include them in your commit. Once all of the modified files have been added to the commit, commit and push the working branch to github.

7. Set up a pull request on GitHub from your working repo to the `openshift.github.com` master branch. Once this pull request is reviewed and merged, the new docs will appear on the site.

