/// Small pure formatting helpers shared by widgets and view-model builders.
library;

const _mb = 1024 * 1024;
const _gb = 1024 * _mb;

/// `411 MB` below 1 GB (whole MB), `1.2 GB` from 1 GB; 1024-based.
String formatBytes(int bytes) => bytes < _gb
    ? '${(bytes / _mb).round()} MB'
    : '${(bytes / _gb).toStringAsFixed(1)} GB';
