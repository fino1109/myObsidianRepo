num=0
for i in $(ls ./resources)
do 
	text=`grep -R $i ./`
	if [ -z "$text" ]; then
		rm -rf "./resources/$i"
		echo removed
		num=$((num+1))
	fi
done
echo "$num removed"

