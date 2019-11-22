#! /bin/bash

# Check for output directory, and create it if missing
if [ ! -d "$output" ]; then
  mkdir output
fi


main(){
	# 1. Defines the content image as a variable
	input=$1
	input_file=`basename $input`
	clean_name="${input_file%.*}"
	
	#Defines the style image as a variable
	style=$2
	style_dir=`dirname $style`
	style_file=`basename $style`
	style_name="${style_file%.*}"
	
	#Defines the output directory
	output="./output"
	out_file=$output/$input_file
	
	#Defines the overlap
	overlap_w=50
	overlap_h=50
	
	# 2. Creates your original styled output. This step will be skipped if you place a previously styled image with the same name 
	# as your specified "content image", located in your Neural-Style/output/<Styled_Image> directory.
	if [ ! -s $out_file ] ; then
		neural_style $input $style $out_file
	fi
	
	# 3. Chop the styled image into 3x3 tiles with the specified overlap value.
	out_dir=$output/$clean_name
	mkdir -p $out_dir
	convert $out_file -crop 4x4+"$overlap_w"+"$overlap_h"@ +repage +adjoin $out_dir/$clean_name"_%d.png"
	
	#Finds out the length and width of the first tile as a refrence point for resizing the other tiles.
	original_tile_w=`convert $out_dir/$clean_name'_0.png' -format "%w" info:`
	original_tile_h=`convert $out_dir/$clean_name'_0.png' -format "%h" info:`
	
	#Resize all tiles to avoid ImageMagick weirdness
	mogrify -path $output/$clean_name/ -resize "$original_tile_w"x"$original_tile_h"\! $output/$clean_name/*.png 					

	#Create original content tyles
	out_dir_oc=$output/origcontent/tiles
	mkdir -p $out_dir_oc
	convert $input_file -crop 4x4+"$overlap_w"+"$overlap_h"@ +repage +adjoin $out_dir_oc/$clean_name"_%d.png"

	#Finds out the length and width of the first original content tile as a refrence point for resizing the other tiles.
	original_content_tile_w=`convert $out_dir_oc/$clean_name'_0.png' -format "%w" info:`
	original_content_tile_h=`convert $out_dir_oc/$clean_name'_0.png' -format "%h" info:`
	
	#Resize all tiles to avoid ImageMagick weirdness
	mogrify -path $output/origcontent/tiles/ -resize "$original_content_tile_w"x"$original_content_tile_h"\! $output/origcontent/$clean_name/*.png 

	# 4. neural-style each tile
	tiles_dir="$out_dir/tiles"
	content_tiles_dir="$out_dir_oc"
	mkdir -p $tiles_dir
	for tile in "${clean_name}_"{0..15}.png
	do
		neural_style_tiled $out_dir/$tile $style $tiles_dir/$tile $content_tiles_dir/$tile
	done
	
	#Perform the required mathematical operations:	

	upres_tile_w=`convert $tiles_dir/$clean_name'_0.png' -format "%w" info:`
	upres_tile_h=`convert $tiles_dir/$clean_name'_0.png' -format "%h" info:`
	
	tile_diff_w=`echo $upres_tile_w $original_tile_w | awk '{print $1/$2}'`
	tile_diff_h=`echo $upres_tile_h $original_tile_h | awk '{print $1/$2}'`

	smush_value_w=`echo $overlap_w $tile_diff_w | awk '{print $1*$2}'`
	smush_value_h=`echo $overlap_h $tile_diff_h | awk '{print $1*$2}'`
	
	# 5. feather tiles
	feathered_dir=$out_dir/feathered
	mkdir -p $feathered_dir
	for tile in "${clean_name}_"{0..15}.png
	do
		tile_name="${tile%.*}"
		convert $tiles_dir/$tile -alpha set -virtual-pixel transparent -channel A -morphology Distance Euclidean:1,50\! +channel "$feathered_dir/$tile_name.png"
	done
	
	# 7. Smush the feathered tiles together
	convert -background transparent \
	    \( $feathered_dir/$clean_name'_0.png' $feathered_dir/$clean_name'_1.png' $feathered_dir/$clean_name'_2.png' $feathered_dir/$clean_name'_3.png' +smush -$smush_value_w -background transparent \) \
	    \( $feathered_dir/$clean_name'_4.png' $feathered_dir/$clean_name'_5.png' $feathered_dir/$clean_name'_6.png' $feathered_dir/$clean_name'_7.png' +smush -$smush_value_w -background transparent \) \
	    \( $feathered_dir/$clean_name'_8.png' $feathered_dir/$clean_name'_9.png' $feathered_dir/$clean_name'_10.png' $feathered_dir/$clean_name'_11.png' +smush -$smush_value_w -background transparent \) \
	    \( $feathered_dir/$clean_name'_12.png' $feathered_dir/$clean_name'_13.png' $feathered_dir/$clean_name'_14.png' $feathered_dir/$clean_name'_15.png' +smush -$smush_value_w -background transparent \) \
		-background none  -background transparent -smush -$smush_value_h  $output/$clean_name.large_feathered.png

	# 8. Smush the non-feathered tiles together
	convert \
	    \( $tiles_dir/$clean_name'_0.png' $tiles_dir/$clean_name'_1.png' $tiles_dir/$clean_name'_2.png' $tiles_dir/$clean_name'_3.png' +smush -$smush_value_w \) \
	    \( $tiles_dir/$clean_name'_4.png' $tiles_dir/$clean_name'_5.png' $tiles_dir/$clean_name'_6.png' $tiles_dir/$clean_name'_7.png' +smush -$smush_value_w \) \
	    \( $tiles_dir/$clean_name'_8.png' $tiles_dir/$clean_name'_9.png' $tiles_dir/$clean_name'_10.png' $tiles_dir/$clean_name'_11.png' +smush -$smush_value_w \) \
	    \( $tiles_dir/$clean_name'_12.png' $tiles_dir/$clean_name'_13.png' $tiles_dir/$clean_name'_14.png' $tiles_dir/$clean_name'_15.png' +smush -$smush_value_w \) \
		-background none -smush -$smush_value_h  $output/$clean_name.large.png

	# 8. Combine feathered and un-feathered output images to disguise feathering.
	composite $output/$clean_name.large_feathered.png $output/$clean_name.large.png $output/$clean_name.large_final.png
}

retry=0

#Runs the content image and style image through Neural-Style with your chosen parameters.
neural_style(){
	echo "Neural Style Transfering "$1
	if [ ! -s $3 ]; then
#####################################################################################
th ../neural_style.lua -seed 100 \
-backend cudnn -cudnn_autotune \
-style_scale 1 -init image -normalize_gradients \
-image_size 256 -num_iterations 2500 -save_iter 50 \
-content_weight 200 -style_weight 1000 \
-style_image $2 \
-content_image $1 \
-output_image out256.png \
-model_file ../../models/VGG_ILSVRC_19_layers.caffemodel -proto_file ../../models/VGG_ILSVRC_19_layers_deploy.prototxt \
-content_layers relu1_1,relu2_1,relu3_1,relu4_1,relu4_2,relu5_1 \
-style_layers relu3_1,relu4_1,relu4_2,relu5_1 \
-tv_weight 0.000085 -original_colors 0 && rm *_*0.png

th ../neural_style.lua -seed 100 \
-backend cudnn -cudnn_autotune \
-style_scale 1 -init image -normalize_gradients \
-image_size 512 -num_iterations 500 -save_iter 50 \
-content_weight 200 -style_weight 1000 \
-style_image $2 \
-content_image $1 \
-init_image out256.png \
-output_image $3 \
-model_file ../../models/VGG_ILSVRC_19_layers.caffemodel -proto_file ../../models/VGG_ILSVRC_19_layers_deploy.prototxt \
-content_layers relu1_1,relu2_1,relu3_1,relu4_1,relu4_2,relu5_1 \
-style_layers relu3_1,relu4_1,relu4_2,relu5_1 \
-tv_weight 0.000085 -original_colors 0 && rm output/content/*_*0.png

#####################################################################################
	fi
	if [ ! -s $3 ] && [ $retry -lt 1 ] ;then
			echo "Transfer Failed, Retrying for $retry time(s)"
			retry=`echo 1 $retry | awk '{print $1+$2}'`
			neural_style $1 $2 $3
	fi
	retry=0
}
retry=0

#Runs the tiles through Neural-Style with your chosen parameters. 
neural_style_tiled(){
	echo "Neural Style Transfering "$1
	if [ ! -s $3 ]; then
#####################################################################################	

th ../neural_style.lua -seed 100 \
-backend cudnn -cudnn_autotune \
-style_scale 1 -init image -normalize_gradients \
-image_size 512 -num_iterations 300 -save_iter 50 \
-content_weight 100 -style_weight 1000 \
-style_image $2 \
-content_image $4 \
-init_image $1 \
-output_image $3 \
-model_file ../../models/VGG_ILSVRC_19_layers.caffemodel -proto_file ../../models/VGG_ILSVRC_19_layers_deploy.prototxt \
-content_layers relu1_1,relu2_1,relu3_1,relu4_1,relu4_2,relu5_1 \
-style_layers relu3_1,relu4_1,relu4_2,relu5_1 \
-tv_weight 0.000085 -original_colors 0 && rm output/content/tiles/content_*_*0.png
 
#####################################################################################
	fi
	if [ ! -s $3 ] && [ $retry -lt 3 ] ;then
			echo "Transfer Failed, Retrying for $retry time(s)"
			retry=`echo 1 $retry | awk '{print $1+$2}'`
			neural_style_tiled $1 $2 $3
	fi
	retry=0
}

main $1 $2 $3