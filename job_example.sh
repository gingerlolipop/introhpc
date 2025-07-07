#!/bin/bash
#SBATCH --time=10:00:00           # Request 10 hours of runtime
#SBATCH --account=st-tlwang-1  # Your CPU allocation code
#SBATCH --nodes=1                 # Request 1 node
#SBATCH --ntasks=1                # Request 1 task
#SBATCH --cpus-per-task=1         # Request 1 CPU per task
#SBATCH --mem=2G                  # Request 2 GB of memory
#SBATCH --job-name=hello_job      # Job name
#SBATCH -e slurm-%j.err           # Error file (%j will be replaced by the job ID)
#SBATCH -o slurm-%j.out           # Output file
#SBATCH --mail-user=jiangjing.gingercrystal@gmail.com  # Your email for notifications
#SBATCH --mail-type=ALL           # Email notifications for all job events

# Load the necessary Python module (adjust the version if needed)
module load python/3.11.6

# Change to the directory where you submitted the job
cd $SLURM_SUBMIT_DIR

# Create a Python virtual environment
source /scratch/st-tlwang-1/jing/myenv/bin/activate


# Create a simple Python script using a here-document
cat > hello.py << 'EOF'
import numpy as np
print("Hello from Sockeye!")
a = np.array([1, 2, 3])
print("Array:", a)
EOF

# Run the Python script
python hello.py
