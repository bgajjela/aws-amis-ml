# Spark/Java environment for all shells
# Defaults to Python 3.13 env; override PYSPARK_PYTHON if desired
export JAVA_HOME=/opt/nix/langs/java
export SPARK_HOME=/opt/nix/langs/spark
export PATH="$SPARK_HOME/bin:$JAVA_HOME/bin:$PATH"

# Default PySpark interpreter (can be overridden by user)
export PYSPARK_PYTHON=${PYSPARK_PYTHON:-/opt/nix/envs/base/bin/python}

# Helper aliases (optional; comment out to disable)
alias pyspark311='PYSPARK_PYTHON=/opt/nix/envs/base/bin/python pyspark'
alias pyspark313='PYSPARK_PYTHON=/opt/nix/envs/base/bin/python pyspark'

