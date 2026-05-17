# shellcheck shell=bash
# Spark/Java environment for all shells (Java 21 LTS)
export JAVA_HOME=/opt/nix/langs/java
export SPARK_HOME=/opt/nix/langs/spark
export PATH="$SPARK_HOME/bin:$JAVA_HOME/bin:$PATH"

# Default PySpark interpreter — override with PYSPARK_PYTHON env var
export PYSPARK_PYTHON=${PYSPARK_PYTHON:-/opt/nix/envs/base/bin/python}

# Spark shuffle / local storage on EBS, not tmpfs.
# /tmp is a tmpfs (nosuid,nodev,noexec,size=25% of RAM). Spark shuffle data
# can exceed that limit on large jobs and is also blocked by noexec.
# /opt/spark-local is on the EBS root volume (24 GB default, expandable).
export SPARK_LOCAL_DIRS=/opt/spark-local

# Per-version PySpark aliases
alias pyspark311='PYSPARK_PYTHON=/opt/nix/envs/base/bin/python pyspark'
alias pyspark312='PYSPARK_PYTHON=/opt/nix/envs/base-py312/bin/python pyspark'
alias pyspark313='PYSPARK_PYTHON=/opt/nix/envs/base-py313/bin/python pyspark'
