abstract final class AppRoutes {
  static const splash = '/splash';
  static const login = '/login';
  static const register = '/register';
  static const home = '/';
  static const search = '/search';

  static const vault = '/vault';
  static const passwords = '/vault/passwords';
  static const passwordNew = '/vault/passwords/new';
  static const passwordGenerator = '/vault/passwords/generator';
  static String passwordDetail(String id) => '/vault/passwords/$id';
  static String passwordEdit(String id) => '/vault/passwords/$id/edit';

  static const documents = '/vault/documents';
  static const documentNew = '/vault/documents/new';
  static String documentDetail(String id) => '/vault/documents/$id';

  static const photos = '/vault/photos';
  static const photoNew = '/vault/photos/new';
  static String photoDetail(String id) => '/vault/photos/$id';

  static const files = '/vault/files';
  static const fileNew = '/vault/files/new';
  static String fileDetail(String id) => '/vault/files/$id';

  static const money = '/money';
  static const accounts = '/money/accounts';
  static const transactions = '/money/transactions';
  static const transactionNew = '/money/transactions/new';

  static const planner = '/planner';
  static const todos = '/planner/todos';
  static const todoNew = '/planner/todos/new';
  static String todoDetail(String id) => '/planner/todos/$id';

  static const notes = '/planner/notes';
  static const noteNew = '/planner/notes/new';
  static String noteDetail(String id) => '/planner/notes/$id';

  static const reminders = '/planner/reminders';
  static const reminderNew = '/planner/reminders/new';
  static String reminderDetail(String id) => '/planner/reminders/$id';

  static const more = '/more';
  static const profile = '/more/profile';
  static const security = '/more/security';
  static const pinSetup = '/more/security/pin';
  static const settings = '/more/settings';
}
