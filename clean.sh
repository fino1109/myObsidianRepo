rem=0
scan=0
for i in $(ls ./resources)
do 
	scan=$((scan+1))
	text=`grep -R $i ./`
	echo "checking $i"
	if [ -z "$text" ]; then
		rm -rf "./resources/$i"
		echo "$i removed"
		rem=$((rem+1))
	fi
done
echo "$scan checked"
echo "$num removed"

