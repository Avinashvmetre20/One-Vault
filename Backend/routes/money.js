import { Router } from "express";
import { requireAuth } from "../middleware/auth.js";
import {
  archiveAccount,
  archiveCard,
  createAccount,
  createCard,
  deleteAccount,
  deleteCard,
  getAccount,
  getCard,
  listAccounts,
  listCards,
  updateAccount,
  updateCard,
} from "../controllers/moneyAccountController.js";
import {
  createCategory,
  createTransaction,
  deleteCategory,
  deleteTransaction,
  getTransaction,
  listCategories,
  listTransactions,
  moneyOverview,
  moneyReports,
  updateCategory,
  updateTransaction,
} from "../controllers/moneyTransactionController.js";

const router = Router();

router.use(requireAuth);

router.get("/overview", moneyOverview);
router.get("/reports", moneyReports);

router.get("/accounts", listAccounts);
router.post("/accounts", createAccount);
router.get("/accounts/:id", getAccount);
router.patch("/accounts/:id", updateAccount);
router.put("/accounts/:id", updateAccount);
router.post("/accounts/:id/archive", archiveAccount);
router.delete("/accounts/:id", deleteAccount);

router.get("/cards", listCards);
router.post("/cards", createCard);
router.get("/cards/:id", getCard);
router.patch("/cards/:id", updateCard);
router.put("/cards/:id", updateCard);
router.post("/cards/:id/archive", archiveCard);
router.delete("/cards/:id", deleteCard);

router.get("/categories", listCategories);
router.post("/categories", createCategory);
router.patch("/categories/:id", updateCategory);
router.put("/categories/:id", updateCategory);
router.delete("/categories/:id", deleteCategory);

router.get("/transactions", listTransactions);
router.post("/transactions", createTransaction);
router.get("/transactions/:id", getTransaction);
router.patch("/transactions/:id", updateTransaction);
router.put("/transactions/:id", updateTransaction);
router.delete("/transactions/:id", deleteTransaction);

router.get("/transfers", (req, res, next) => {
  req.query.type = "transfer";
  return listTransactions(req, res, next);
});
router.post("/transfers", (req, res, next) => {
  req.body = { ...req.body, transactionType: req.body.transactionType || "transfer" };
  return createTransaction(req, res, next);
});

export default router;
