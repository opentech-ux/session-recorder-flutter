library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'package:http/io_client.dart';

import 'package:session_recorder_flutter/src/constants/gestures_constants.dart';
import 'package:session_recorder_flutter/src/constants/version_constant.dart';
import 'package:session_recorder_flutter/src/controllers/inactivity_detector.dart';
import 'package:session_recorder_flutter/src/enums/gestures_type_enum.dart';
import 'package:session_recorder_flutter/src/observers/session_recorder_observer.dart';
import 'package:session_recorder_flutter/src/tree/lom_tree_config.dart';
import 'package:session_recorder_flutter/src/tree/lom_tree_inspector.dart';
import 'package:session_recorder_flutter/src/tree/tap_tree_resolver.dart';
import 'package:session_recorder_flutter/src/utils/math_utils.dart';
import 'package:session_recorder_flutter/src/utils/session_logger.dart';

import 'models/models.dart';

part 'tree/tree_detector.dart';
part 'session/session_recorder.dart';
part 'collectors/scroll_collector.dart';
part 'collectors/gestures_collector.dart';
part 'widgets/session_recorder_widget.dart';
part 'observers/session_lifecycle_observer.dart';
part 'observers/session_navigator_observer.dart';
