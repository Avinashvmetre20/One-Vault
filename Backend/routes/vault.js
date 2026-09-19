import { Router } from "express";
import { requireAuth } from "../middleware/auth.js";
import {
  createPassword,
  deletePassword,
  getPassword,
  listPasswords,
  setupVault,
  unlockVault,
  updatePassword,
  vaultStatus,
} from "../controllers/vaultController.js";

const router = Router();

router.use(requireAuth);

router.get("/status", vaultStatus);
router.post("/setup", setupVault);
router.post("/unlock", unlockVault);
router.get("/passwords", listPasswords);
router.post("/passwords", createPassword);
router.get("/passwords/:id", getPassword);
router.patch("/passwords/:id", updatePassword);
router.delete("/passwords/:id", deletePassword);

export default router;
