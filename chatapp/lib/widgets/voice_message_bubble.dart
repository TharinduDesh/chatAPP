import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'dart:async';

class VoiceMessageBubble extends StatefulWidget {
  final String audioUrl;
  final bool isMe;

  const VoiceMessageBubble({
    super.key,
    required this.audioUrl,
    required this.isMe,
  });

  @override
  State<VoiceMessageBubble> createState() => _VoiceMessageBubbleState();
}

class _VoiceMessageBubbleState extends State<VoiceMessageBubble> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  StreamSubscription? _playerStateSubscription;
  StreamSubscription? _durationSubscription;
  StreamSubscription? _positionSubscription;

  PlayerState? _playerState;
  Duration? _duration;
  Duration? _position;

  // NEW: State to track if the player is ready
  bool _isPlayerInitialized = false;

  bool get _isPlaying => _playerState?.playing ?? false;
  bool get _isLoading =>
      _playerState?.processingState == ProcessingState.loading ||
      _playerState?.processingState == ProcessingState.buffering;

  @override
  void initState() {
    super.initState();
    // We only listen to streams now, we don't load the URL yet.
    _playerStateSubscription = _audioPlayer.playerStateStream.listen((state) {
      if (mounted) setState(() => _playerState = state);
    });
    _durationSubscription = _audioPlayer.durationStream.listen((duration) {
      if (mounted) setState(() => _duration = duration);
    });
    _positionSubscription = _audioPlayer.positionStream.listen((position) {
      if (mounted) setState(() => _position = position);
    });
  }

  @override
  void dispose() {
    _playerStateSubscription?.cancel();
    _durationSubscription?.cancel();
    _positionSubscription?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }

  // MODIFIED: This is the core of the lazy loading logic
  Future<void> _handlePlayPause() async {
    // If player is already playing, just pause it.
    if (_isPlaying) {
      _audioPlayer.pause();
      return;
    }

    // If the player has not been initialized yet...
    if (!_isPlayerInitialized) {
      try {
        // ...set the URL and wait for it to load.
        await _audioPlayer.setUrl(widget.audioUrl);
        setState(() {
          _isPlayerInitialized = true;
        });
      } catch (e) {
        print("Error loading audio source: $e");
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Error: Could not load audio.")),
        );
        return; // Don't proceed to play if loading failed
      }
    }

    // Now, play the audio.
    _audioPlayer.play();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = widget.isMe ? Colors.white : Colors.black87;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            // MODIFIED: Use the new handler method
            onPressed: _handlePlayPause,
            icon:
                _isLoading
                    ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: color,
                      ),
                    )
                    : Icon(
                      _isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                    ),
            color: color,
            iconSize: 30,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 6.0,
                    ),
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 12.0,
                    ),
                    trackHeight: 2.0,
                  ),
                  child: Slider(
                    min: 0.0,
                    max: (_duration?.inMilliseconds ?? 1).toDouble(),
                    value: (_position?.inMilliseconds ?? 0).toDouble().clamp(
                      0.0,
                      (_duration?.inMilliseconds ?? 1).toDouble(),
                    ),
                    onChanged: (value) {
                      _audioPlayer.seek(Duration(milliseconds: value.round()));
                    },
                    activeColor:
                        widget.isMe
                            ? theme.colorScheme.onPrimary.withOpacity(0.8)
                            : theme.primaryColor,
                    inactiveColor:
                        widget.isMe
                            ? theme.colorScheme.onPrimary.withOpacity(0.3)
                            : Colors.grey.shade300,
                  ),
                ),
                Text(
                  _formatDuration(_position ?? Duration.zero) +
                      " / " +
                      _formatDuration(_duration ?? Duration.zero),
                  style: TextStyle(fontSize: 11, color: color.withOpacity(0.8)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return "$minutes:$seconds";
  }
}
