export const publicUser = (user) => ({
  userId: user.user_id,
  name: user.name,
  email: user.email,
  phone: user.phone,
  createdAt: user.created_at,
  updatedAt: user.updated_at,
});
