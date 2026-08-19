class IntegrityDiagnostic {
  final String? stage;
  final String? code;
  final String? message;
  final String? details;
  final int? cloudProjectNumber;
  final int? nonceLength;
  final bool? tokenReceived;
  final int? tokenLength;
  final int? backendStatus;
  final bool? requestDetailsPresent;
  final bool? requestHashPresent;
  final bool? requestHashMatches;
  final int? tokenAgeSeconds;
  final bool? appIntegrityPresent;
  final String? appRecognitionVerdict;
  final String? packageName;
  final bool? packageNameMatches;
  final bool? deviceIntegrityPresent;
  final List<String>? deviceRecognitionVerdict;
  final bool? licensingPresent;
  final String? licensingVerdict;
  final bool? decodeSuccess;
  final String? errorType;
  final String? errorMessage;
  final List<String>? failedChecks;

  const IntegrityDiagnostic({
    this.stage,
    this.code,
    this.message,
    this.details,
    this.cloudProjectNumber,
    this.nonceLength,
    this.tokenReceived,
    this.tokenLength,
    this.backendStatus,
    this.requestDetailsPresent,
    this.requestHashPresent,
    this.requestHashMatches,
    this.tokenAgeSeconds,
    this.appIntegrityPresent,
    this.appRecognitionVerdict,
    this.packageName,
    this.packageNameMatches,
    this.deviceIntegrityPresent,
    this.deviceRecognitionVerdict,
    this.licensingPresent,
    this.licensingVerdict,
    this.decodeSuccess,
    this.errorType,
    this.errorMessage,
    this.failedChecks,
  });

  factory IntegrityDiagnostic.fromJson(Map<String, dynamic> json) {
    return IntegrityDiagnostic(
      stage: json['stage'] as String?,
      code: json['code'] as String?,
      message: json['message'] as String?,
      details: json['details'] as String?,
      cloudProjectNumber: json['cloudProjectNumber'] as int?,
      nonceLength: json['nonceLength'] as int?,
      tokenReceived: json['tokenReceived'] as bool?,
      tokenLength: json['tokenLength'] as int?,
      backendStatus: json['backendStatus'] as int?,
      requestDetailsPresent: json['requestDetailsPresent'] as bool?,
      requestHashPresent: json['requestHashPresent'] as bool?,
      requestHashMatches: json['requestHashMatches'] as bool?,
      tokenAgeSeconds: json['tokenAgeSeconds'] as int?,
      appIntegrityPresent: json['appIntegrityPresent'] as bool?,
      appRecognitionVerdict: json['appRecognitionVerdict'] as String?,
      packageName: json['packageName'] as String?,
      packageNameMatches: json['packageNameMatches'] as bool?,
      deviceIntegrityPresent: json['deviceIntegrityPresent'] as bool?,
      deviceRecognitionVerdict: (json['deviceRecognitionVerdict'] as List<dynamic>?)?.cast<String>(),
      licensingPresent: json['licensingPresent'] as bool?,
      licensingVerdict: json['licensingVerdict'] as String?,
      decodeSuccess: json['decodeSuccess'] as bool?,
      errorType: json['errorType'] as String?,
      errorMessage: json['errorMessage'] as String?,
      failedChecks: (json['failedChecks'] as List<dynamic>?)?.cast<String>(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'stage': stage,
      'code': code,
      'message': message,
      'details': details,
      'cloudProjectNumber': cloudProjectNumber,
      'nonceLength': nonceLength,
      'tokenReceived': tokenReceived,
      'tokenLength': tokenLength,
      'backendStatus': backendStatus,
      'requestDetailsPresent': requestDetailsPresent,
      'requestHashPresent': requestHashPresent,
      'requestHashMatches': requestHashMatches,
      'tokenAgeSeconds': tokenAgeSeconds,
      'appIntegrityPresent': appIntegrityPresent,
      'appRecognitionVerdict': appRecognitionVerdict,
      'packageName': packageName,
      'packageNameMatches': packageNameMatches,
      'deviceIntegrityPresent': deviceIntegrityPresent,
      'deviceRecognitionVerdict': deviceRecognitionVerdict,
      'licensingPresent': licensingPresent,
      'licensingVerdict': licensingVerdict,
      'decodeSuccess': decodeSuccess,
      'errorType': errorType,
      'errorMessage': errorMessage,
      'failedChecks': failedChecks,
    };
  }

  String toDiagnosticString() {
    final buffer = StringBuffer();
    buffer.writeln('Google Play Integrity Diagnostic');
    buffer.writeln('');
    
    if (stage != null) {
      buffer.writeln('Stage: $stage');
    }
    if (backendStatus != null) {
      buffer.writeln('Backend status: $backendStatus');
    }
    if (appRecognitionVerdict != null) {
      buffer.writeln('App recognition: $appRecognitionVerdict');
    }
    if (packageName != null) {
      buffer.writeln('Package: $packageName');
    }
    if (packageNameMatches != null) {
      buffer.writeln('Package matches: ${packageNameMatches! ? 'true' : 'false'}');
    }
    if (requestHashMatches != null) {
      buffer.writeln('Request hash: ${requestHashMatches! ? 'MATCH' : 'MISMATCH'}');
    }
    if (deviceRecognitionVerdict != null && deviceRecognitionVerdict!.isNotEmpty) {
      buffer.writeln('Device integrity: ${deviceRecognitionVerdict!.join(', ')}');
    }
    if (licensingVerdict != null) {
      buffer.writeln('Licensing: $licensingVerdict');
    }
    if (tokenAgeSeconds != null) {
      buffer.writeln('Token age: ${tokenAgeSeconds}s');
    }
    if (code != null) {
      buffer.writeln('Code: $code');
    }
    if (message != null) {
      buffer.writeln('Message: $message');
    }
    if (details != null) {
      buffer.writeln('Details: $details');
    }
    if (decodeSuccess != null) {
      buffer.writeln('Decode success: ${decodeSuccess! ? 'true' : 'false'}');
    }
    if (errorType != null) {
      buffer.writeln('Error type: $errorType');
    }
    if (errorMessage != null) {
      buffer.writeln('Error: $errorMessage');
    }
    
    return buffer.toString();
  }
}