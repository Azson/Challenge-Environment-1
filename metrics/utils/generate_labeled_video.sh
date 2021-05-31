#!/bin/sh

##################################################################################
# DEFAULT VALUES
##################################################################################

VIDEO_SAMPLE_URL=https://archive.org/download/e-dv548_lwe08_christa_casebeer_003.ogg/e-dv548_lwe08_christa_casebeer_003.mp4
WIDTH=1280
HEIGHT=720
VIDEO_DURATION=00:00:30
PADDING_DURATION_SEC=5
FPS=30
AUDIO_SAMPLE_RATE_HZ=48000
TONE_FREQUENCY_HZ=1000
AUDIO_CHANNELS_NUMBER=2
FFMPEG_LOG="-loglevel error"
TARGET_VIDEO=output/test.yuv
TARGET_AUDIO=output/test.wav
GENERATE_DEFAULT_REF=false
DEFAULT_VIDEO_REF=../test-no-padding.yuv
DEFAULT_AUDIO_REF=../test-no-padding.wav
FONT=/usr/share/fonts/truetype/msttcorefonts/Arial.ttf
CLEANUP=true
USE_URL=false
SUFFIX=y4m
PADDING=false
EXTRACT_WAV=false
USAGE="Usage: `basename $0` [-vr=video_reference] [-d=duration] [-w=width] [-h=height] [--fps=fps] [--suffix=suffix] \
         [-vo=video_output_path] [-ao=audio_output_path] [--no_cleanup] [--clean] [--extract_wav]"

##################################################################################
# FUNCTIONS
##################################################################################

cleanup() {
   echo "Deleting temporal files"
   rm -rf test-no-frame-number.$SUFFIX test-no-padding.$SUFFIX padding.$SUFFIX test.$SUFFIX
}


##################################################################################
# PARSE ARGUMENTS
##################################################################################

for i in "$@"; do
   case $i in
      --game)
      VIDEO_SAMPLE_URL=https://ia802808.us.archive.org/6/items/ForniteBattle8/fornite%20battle%202.mp4
      WIDTH=1280
      HEIGHT=720
      USE_URL=true
      shift
      ;;
      --generate_default_ref)
      GENERATE_DEFAULT_REF=true
      shift
      ;;
      -vr=*|--video_ref=*)
      VIDEO_REF="${i#*=}"
      shift
      ;;
      -d=*|--duration=*)
      VIDEO_DURATION="${i#*=}"
      shift
      ;;
      -w=*|--width=*)
      WIDTH="${i#*=}"
      shift
      ;;
      -h=*|--height=*)
      HEIGHT="${i#*=}"
      shift
      ;;
      --fps=*)
      FPS="${i#*=}"
      shift
      ;;
      -ar=*|--audio_sample_rate=*)
      AUDIO_SAMPLE_RATE_HZ="${i#*=}"
      shift
      ;;
      -ac=*|--audio_channels=*)
      AUDIO_CHANNELS_NUMBER="${i#*=}"
      shift
      ;;
      --extract_wav)
      EXTRACT_WAV=true
      shift
      ;;
      --suffix=*)
      SUFFIX="${i#*=}"
      shift
      ;;
      --padding=*)
      PADDING=true
      shift
      ;;
      -p=*|--padding=*)
      PADDING_DURATION_SEC="${i#*=}"
      shift
      ;;
      -vo=*)
      TARGET_VIDEO="${i#*=}"
      shift
      ;;
      -ao=*)
      TARGET_AUDIO="${i#*=}"
      shift
      ;;
      --no_cleanup)
      CLEANUP=false
      shift
      ;;
      --clean)
      cleanup
      exit 0
      shift
      ;;
      *) # unknown option
      echo $USAGE
      exit 0
      ;;
   esac
done

##################################################################################
# INIT
##################################################################################
mkdir -p output

##########################
# 1. Download video sample
##########################

if [ $USE_URL = true ]; then
    VIDEO_SAMPLE_NAME=$(echo ${VIDEO_SAMPLE_URL##*/} | sed -e 's/%20/ /g')
    echo "Content video ($VIDEO_SAMPLE_NAME) not exits ... downloading"
    wget $VIDEO_SAMPLE_URL
else
    VIDEO_SAMPLE_NAME=$VIDEO_REF
    echo "Content video ($VIDEO_SAMPLE_NAME) already exits"
fi

#######################
# 2. Cut original video
#######################
echo "Cutting original video"
if [ "$SUFFIX" = "yuv" ]; then
   ffmpeg $FFMPEG_LOG -y -video_size "$WIDTH"x"$HEIGHT" -i "$VIDEO_SAMPLE_NAME" -vf scale="$WIDTH:$HEIGHT",setsar=1:1 -r $FPS test-no-frame-number.$SUFFIX
else
   ffmpeg $FFMPEG_LOG -y -i "$VIDEO_SAMPLE_NAME" -vf scale="$WIDTH:$HEIGHT",setsar=1:1 -r $FPS test-no-frame-number.$SUFFIX
fi

#########################
# 3. Overlay frame number
#########################
echo "Overlaying frame number in the video content"
if [ "$SUFFIX" = "yuv" ]; then
   ffmpeg $FFMPEG_LOG -y -video_size "$WIDTH"x"$HEIGHT" -i test-no-frame-number.$SUFFIX -vf drawtext="fontfile=$FONT:text='\   %{frame_num}  \ ':start_number=1:x=(w-tw)/2:y=h-(2*lh)+15:fontcolor=black:fontsize=40:box=1:boxcolor=white:boxborderw=10" test-no-padding.$SUFFIX
else
   ffmpeg $FFMPEG_LOG -y -i test-no-frame-number.$SUFFIX -vf drawtext="fontfile=$FONT:text='\   %{frame_num}  \ ':start_number=1:x=(w-tw)/2:y=h-(2*lh)+15:fontcolor=black:fontsize=40:box=1:boxcolor=white:boxborderw=10" test-no-padding.$SUFFIX
fi
cp test-no-padding.$SUFFIX test.$SUFFIX

#################################################
# 4. Create padding video based on a test pattern
#################################################
if $PADDING; then
echo "Creating padding video ($PADDING_DURATION_SEC seconds)"
ffmpeg $FFMPEG_LOG -y -f lavfi -i testsrc=duration=$PADDING_DURATION_SEC:size="$WIDTH"x"$HEIGHT":rate=$FPS -f lavfi -i sine=frequency=$TONE_FREQUENCY_HZ:duration=$PADDING_DURATION_SEC padding.$SUFFIX
fi

############################
# 5. Concatenate final video
############################
if $PADDING; then
   echo "Concatenating padding and content videos"
   ffmpeg $FFMPEG_LOG -y -i padding.$SUFFIX -i test-no-padding.$SUFFIX -i padding.$SUFFIX -filter_complex concat=n=3:v=1:a=1 test.$SUFFIX
fi

#########################
# 6. Convert video to YUV
#########################
echo "Converting resulting video to YUV ($TARGET_VIDEO)"
if [ "$SUFFIX" = "yuv" ]; then
   ffmpeg $FFMPEG_LOG -y -video_size "$WIDTH"x"$HEIGHT" -i test.$SUFFIX -pix_fmt yuv420p $TARGET_VIDEO
else
   ffmpeg $FFMPEG_LOG -y -i test.$SUFFIX -pix_fmt yuv420p $TARGET_VIDEO
fi

#########################
# 7. Convert audio to WAV
#########################
if $EXTRACT_WAV; then
   echo "Converting resulting audio to WAV ($TARGET_AUDIO)"
   ffmpeg $FFMPEG_LOG -y -i test.$SUFFIX -vn $TARGET_AUDIO
fi

###############################
# 8. Generate default reference
###############################
if $GENERATE_DEFAULT_REF; then
   echo "Generating default video reference ($DEFAULT_VIDEO_REF)"
   ffmpeg $FFMPEG_LOG -y -i test-no-padding.$SUFFIX -pix_fmt yuv420p -c:v rawvideo -an $DEFAULT_VIDEO_REF

   echo "Generating default audio reference ($DEFAULT_AUDIO_REF)"
   ffmpeg $FFMPEG_LOG -y -i test-no-padding.$SUFFIX -vn -acodec pcm_s16le -ar $AUDIO_SAMPLE_RATE_HZ -ac $AUDIO_CHANNELS_NUMBER $DEFAULT_AUDIO_REF
fi

################################
# 9. Delete temporal video files
################################
if $CLEANUP; then
   cleanup
fi
