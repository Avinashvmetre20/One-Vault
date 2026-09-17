import { Router } from "express";
import { requireAuth } from "../middleware/auth.js";
import {
  deleteVaultCredential,
  getVaultMeta,
  listVaultCredentials,
  putVaultMeta,
  upsertVaultCredential,
} from "../controllers/vaultController.js";

const router = Router();

router.use(requireAuth);

router.get("/meta", getVaultMeta);
router.put("/meta", putVaultMeta);
router.get("/credentials", listVaultCredentials);
router.put("/credentials/:id", upsertVaultCredential);
router.delete("/credentials/:id", deleteVaultCredential);

export default router;
