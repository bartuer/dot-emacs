dir /Users/bartuer/local/src/selfie/embeded/jxcore/deps/facecore/deps/facesdk
cd /Users/bartuer/local/src/selfie/embeded/jxcore
target remote 192.168.0.126:5858
b facesdk::detection::JointCascadeFaceDetector::JointCascadePredictProductionHighEndModel
b JointCascadeFaceDetectorPredictHighEndModel.cpp:595
b JointCascadeFaceDetectorPredictHighEndModel.cpp:596



