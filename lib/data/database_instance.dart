import 'app_database.dart';

// ---------------------------------------------------------------------------
// The one shared database for the whole app.
//
// Why a separate file: if the screens imported main.dart to reach the
// database, main.dart and the screens would import each other (a circular
// import), which is messy. A small file that both can import avoids that.
//
// Why only one instance: opening the same database file twice creates two
// separate connections that do not see each other's changes properly.
// ---------------------------------------------------------------------------
final AppDatabase db = AppDatabase();
