#!/bin/bash
set -e
set -o pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
REGISTRY_URL="${REGISTRY_URL:-114416042199.dkr.ecr.us-west-2.amazonaws.com}"
REPO_NAME="${REPO_NAME:-de-tools-and-services}"
JOBS=${JOBS:-1}

ERRORS="$(pwd)/errors"

build_and_push(){
	tag=$1
	build_dir=$2

	full_tag=${REGISTRY_URL}/${REPO_NAME}:${tag}

	# If image already in repo then do nothing.
	echo "--images--"
	val=$(aws ecr list-images --repository-name ${REPO_NAME} --no-paginate --query 'imageIds[?imageTag==`'${tag}'`]' --output text)
	if [[ `echo ${val}` ]]; then
		echo "Image '${tag}' already exists in the ${REPO_NAME} repository"
		docker pull ${full_tag}
	else
		echo "[BUILD] Building ${full_tag} for context ${build_dir}"
		docker build --rm --force-rm -t ${full_tag} ${build_dir} || return 1

		# on successful build, push the image
		echo "[BUILD] Finished building ${tag} with context ${build_dir}"

		# try push 2 times in case first push fails
		n=0
		until [ $n -ge 2 ]; do
			docker push ${full_tag} && break
			echo "[BUILD] Try #$n failed... sleeping for 15 seconds"
			n=$[$n+1]
			sleep 5
		done
	fi
}

process_dockerfile() {
	sha1_date=$1                     # e.g. 93c324b4c3_2018-05-20
	file_path=$2                     # e.g. docs-html/app/Dockerfile
	build_dir=$(dirname $file_path)  # e.g. docs-html/app

	# Count the slashes in ${build_dir} to make sure that all services are nesting their
	# Dockerfiles one level deep. 
	build_dir_depth=$(echo $build_dir | grep -o / | wc -l)
	if (( $build_dir_depth  != 1 )); then
		echo "Error: Dockerfiles must be nested exactly one level deep: ${build_dir}." 1>&2
		exit 1
	fi

	image=${file_path%Dockerfile}    # e.g. docs-html/app/

	# Use the first token in image as the tag_base:  docs-html/app/-> docs-html
	tag_base=${image%%\/*}  

	# Use the last token in build_dir as the tag_version:  docs-html/app -> app
	tag_version=${build_dir##*\/}

	if [[ -z "$tag_version" ]] || [[ "$tag_version" == "$tag_base" ]]; then
		echo "Error: Could not determine tag_version value for: ${file_path}" 1>&2
		exit 1
	fi

	# Append the sha1_date to the tag_version
	tag=${tag_base}-${tag_version}-${sha1_date}

	# Show the final parsed values
	echo build_dir=${build_dir}
	echo image_tag=${tag}


	{
		$SCRIPT build_and_push "${tag}" "${build_dir}"
	} || {
		# add to errors
		echo "${tag}" >> $ERRORS
	}

	# Also push the latest tag
	docker tag ${REGISTRY_URL}/${REPO_NAME}:${tag} ${REGISTRY_URL}/${REPO_NAME}:${tag_base}-${tag_version}-latest
	docker push ${REGISTRY_URL}/${REPO_NAME}:${tag_base}-${tag_version}-latest

echo
echo
}

main(){
	# make sure that there are no uncommmited git changes.
	# except for build.sh, which is ok to have modified for some reason.
	if [[ `git status --porcelain | grep -v ' M ops/services/build.sh'` ]]; then
		git status --porcelain
		echo
		echo "[ERROR] There are uncommited changes in the work tree." >&2
		echo "[ERROR] Please commit changes or checkout a clean branch before building." >&2
		echo
		exit 1
	fi

	# find the dockerfiles
	IFS=$'\n'
	files=( $(find . -iname '*Dockerfile' | sed 's|./||' | sort) )
	unset IFS

	# determine the sha1
	sha1=$(git rev-parse HEAD | cut -c-10)
	sha1_date=${sha1}_$(git show -s --format="%ci" "${sha1}" | awk '{print $1}')
	echo $sha1_date

	# build all dockerfiles
	echo "Running in parallel with ${JOBS} jobs."
	parallel --tag --verbose --ungroup -j"${JOBS}" $SCRIPT process_dockerfile ${sha1_date} "{1}" ::: "${files[@]}"

	if [[ ! -f $ERRORS ]]; then
		echo "No errors, hooray!"
	else
		echo "[ERROR] Some images did not build correctly, see below." >&2
		echo "These images failed: $(cat $ERRORS)" >&2
		exit 1
	fi
}

run(){
	args=$@
	first_arg=$1

	if [[ "$first_arg" == "" ]]; then
		main $args
	else
		$args
	fi
}

run $@

# NOTE: To build a single image run 
# $ ./build.sh process_dockerfile <path-to-dockerfile>/Dockerfile 