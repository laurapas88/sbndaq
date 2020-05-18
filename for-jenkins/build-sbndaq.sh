#!/bin/bash

#parameters

PRODUCTS=/cvmfs/fermilab.opensciencegrid.org/products/artdaq:/cvmfs/fermilab.opensciencegrid.org/products/larsoft

artdaq_version="v3_08_00"

project_name=sbndaq
project_url=https://cdcvs.fnal.gov/projects/${project_name}


#main script
export PRODUCTS

usage() {
  cat 1>&2 <<EOF
Usage: $(basename ${0}) [-h]
       $(basename ${0})  <branchtag> <qual_set> <buildtype>
       env WORKSPACE=<workspace> BRANCHTAG=<develop|master|vN_NN_NN> QUAL=<qualifiers> BUILDTYPE=<debug|prof> $(basename ${0})
EOF
}


while getopts :h OPT; do
  case ${OPT} in
    h)
      usage
      exit 1
      ;;
    *)
      usage
      exit 1
  esac
done
shift $(expr $OPTIND - 1)
OPTIND=1


working_dir="${WORKSPACE:-$(pwd)}"
branchtag="${1:-${BRANCHTAG}}"
qual_set="${2:-${QUAL}}"
build_type="${3:-${BUILDTYPE}}"

IFS=':' read -r -a quals <<< "$qual_set"

for onequal in "${quals[@]}"; do
  case ${onequal} in
    e[679]|e1[0-9]|c[0-9])
      basequal=${onequal}
      ;;
    s7[0-9]|s8[0-9]|s9[0-9])
      squal=${onequal}
      ;;
    py2|py3)
      pyqual=${onequal}
      ;;
    debug|prof)
      build_type=${onequal}
      ;;
    *)
      echo "ERROR: unsupported build qualifier \"${onequal}\""
      usage
      exit 1
  esac
done


qual_set="${basequal}"
[[ ! -z "${pyqual+x}" ]] && qual_set="${qual_set}:${pyqual}"
qual_set="${qual_set}:${squal}"

manifest_qual_set="${squal}:${basequal}"
[[ ! -z "${pyqual+x}" ]] &&  manifest_qual_set="${manifest_qual_set}:${pyqual}"

case ${build_type} in
  debug) build_type_flag="-d" ;;
  prof) build_type_flag="-p" ;;
  *)
    echo "ERROR: build type must be debug or prof"
    usage
    exit 1
esac



# Find platform flavor.
OS=$(uname)
if [ "${OS}" = "Linux" ]
then
  id=$(lsb_release -is)
  if [ "${id}" = "Ubuntu" ]
  then
    flvr=u$(lsb_release -r | sed -e 's/[[:space:]]//g' | cut -f2 -d":" | cut -f1 -d".")
  else
    flvr=slf$(lsb_release -r | sed -e 's/[[:space:]]//g' | cut -f2 -d":" | cut -f1 -d".")
  fi
else
  echo "ERROR: unrecognized operating system ${OS}"
  exit 1
fi


echo "build variables"
echo " working_dir=${working_dir}"
echo " branchtag=${branchtag}"
echo " qual_set=${qual_set}"
echo " build_type=${build_type}"
echo " flvr=${flvr}"


#set -x

product_name=${project_name//-/_}

src_dir=${working_dir}/source
build_dir=${working_dir}/build
products_dir=${working_dir}/products
copyback_dir=${working_dir}/copyBack



# start with clean directories
(cd "${working_dir}"; ls -l; du -sh *)
rm -rf ${build_dir}
rm -rf ${src_dir}
rm -rf ${copyback_dir}
# now make the dfirectories
mkdir -p ${src_dir} || exit 1
mkdir -p ${build_dir} || exit 1
mkdir -p ${copyback_dir} || exit 1
(cd "${working_dir}"; ls -l; du -sh *)



echo
echo "checkout source"
echo
cd ${src_dir} || exit 1
ls -la
git clone ${project_url} ${product_name}
cd ${product_name} || exit 1
git checkout ${branchtag}



echo
echo "pull products from scisoft"
echo
#unset PRODUCTS
[[ ! -d ${products_dir} ]] && mkdir -p ${products_dir}
cd ${products_dir} || exit 1
curl --fail --silent --location --insecure -O http://scisoft.fnal.gov/scisoft/bundles/tools/pullProducts || exit 1
curl --fail --silent --location --insecure -O http://scisoft.fnal.gov/scisoft/bundles/tools/pullPackage || exit 1
chmod +x pullProducts pullPackage
./pullProducts ${products_dir} ${flvr} artdaq-${artdaq_version} ${manifest_qual_set//:/-} ${build_type} 2>&1 |tee ${products_dir}/pullproducts.log

./pullPackage ${products_dir} sl7 python-v3_7_2 2>&1 |tee -a ${products_dir}/pullProducts.log

echo
echo "generate manifest using product_deps and pull products from scisoft"
echo
#unset PRODUCTS
source ${products_dir}/setup || exit 1

setup python v3_7_2
[[ -d ${working_dir}/python3_env ]] && rm -rf ${working_dir}/python3_env
python3 -m venv ${working_dir}/python3_env
source  ${working_dir}/python3_env/bin/activate
pip install --upgrade pip
pip install pandas

local_manifest=${product_name}-current-Linux64bit+3.10-2.17-${manifest_qual_set//:/-}-${build_type}_MANIFEST.txt

python3 ${src_dir}/${product_name}/for-jenkins/generate-manifest.py \
	-p ${src_dir}/${product_name}/ups/product_deps \
  -m ${products_dir}/${local_manifest} \
	-q ${qual_set}:${build_type}

#sed -i '/windriver/d' ${products_dir}/${local_manifest}

cd ${products_dir} || exit 1

./pullProducts -l  ${products_dir} ${flvr} ${product_name}-current ${manifest_qual_set//:/-} ${build_type} 2>&1 |tee -a ${products_dir}/pullproducts.log


table_qual_set="+${qual_set//:/+:}+:${build_type}"
export products_dir

cat ${products_dir}/sbndaq_artdaq/*/ups/sbndaq_artdaq.table | \
        sed -n '/+e19:+py2:+s94:+prof/,/^$/p' | \
        sed  's/setupRequired(/.\/pullPackage ${products_dir} sl7 /g' | \
        sed  's/)//g;s/+//g;s/^[ \t]*//;s/[ \t]*$//;/^\s*$/d;s/:/-/g;s/-q//g;s/\(.*\)-/\1 /'| \
        sort -u | \
        sed 's/ v/-v/g' | bash

unsetup_all

echo
product_version=$(cat  ${src_dir}/${product_name}/ups/product_deps | grep -E "^parent.*${product_name}.*v.*"| grep -Eo "v[0-9]_[0-9]{2}_[0-9]{2}.*")
echo "building the ${product_name} distribution for ${product_version} ${qual_set} ${build_type}"
echo
[[ -d ${build_dir} ]] && rm -rf ${build_dir}
[[ ! -d ${build_dir} ]] && mkdir -p ${build_dir}
cd ${build_dir} || exit 1
source ${products_dir}/setup || exit 1
source ${src_dir}/${product_name}/ups/setup_for_development  ${build_type_flag}  ${qual_set//:/ }
export MRB_QUALS="${qual_set}:${build_type}"
previnstall_dir=${products_dir}/${product_name}/${product_version}
[[ -d ${previnstall_dir} ]] && rm -rf ${previnstall_dir}{,version}

buildtool -I "${products_dir}" -pi -j$(nproc) 2>&1 | tee ${build_dir}/build-${product_name}.log || \
 { mv ${build_dir}/*.log  ${copyback_dir}/
   exit 1
 }

buildtool -t -j$(nproc) 2>&1 | tee ${build_dir}/test-${product_name}.log || \
 { mv ${build_dir}/*.log  ${copyback_dir}/
   exit 1
 }

echo
echo "move files"
echo
mv ${build_dir}/{*.bz2,*.log}  ${copyback_dir}/
mv ${products_dir}/*.log  ${copyback_dir}/



echo
echo "cleanup"
echo
rm -rf "${build_dir}"
rm -rf "${src_dir}"

exit 0