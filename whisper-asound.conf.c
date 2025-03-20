# Simple configuration for the webcam
defaults.pcm.card 1
defaults.ctl.card 1

pcm.webcam {
  type hw
  card 1
  device 0
}

# Simple default to use the webcam
pcm.!default {
  type plug
  slave.pcm "webcam"
}

ctl.!default {
  type hw
  card 1
}