SALVEIFS=$IFS
IFS=$(echo -en "\n\b")
rem=0
scan=0
for i in $(ls ./resources)
do 
	scan=$((scan+1))
	text=`grep -R $i --exclude-dir={.git/,.obsidian/,.idea/,resources/} ./`
	echo "checking $i"
	if [ -z "$text" ]; then
		rm -rf "./resources/$i"
		echo "$i removed"
		rem=$((rem+1))
	fi
done
IFS=$SAVEIFS
echo "$scan checked"
echo "$rem removed"

