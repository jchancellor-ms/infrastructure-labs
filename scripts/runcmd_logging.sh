LOG_DIR="/var/lib/runcommand/logs"
SCRIPT_DIR="/var/lib/waagent/run-command/download"
#check the output file location (create if not exists)
if [ ! -d "$LOG_DIR"]; then
    mkdir $LOG_DIR
fi
#Recurse the waagent download runcommand directory


for i in $(ls -R | grep :); do
    DIR=${i%:}                    # Strip ':'
    cd $DIR
    FILEDATE=(ls)
    awk '{print " " $0}' script.sh > "$LOG_DIR\"                            # Your command
    cd $SCRIPT_DIR
done

#if marker doesn't exist
#create the log output file in a log output location
awk '{print " " $0}' script.sh > /var/lib/runcommand/logs
#create the marker file in the runcmd directory