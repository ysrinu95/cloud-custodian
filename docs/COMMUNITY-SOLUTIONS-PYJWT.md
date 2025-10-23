# Cloud Custodian c7n-mailer PyJWT Issue - Community Solutions

## 🎯 **Issue Summary**
**GitHub Issue:** [#10282 - c7n-mailer PyJWT Import Error](https://github.com/cloud-custodian/cloud-custodian/issues/10282)

**Error:** `Runtime.ImportModuleError: Unable to import module 'periodic': No module named 'jwt'`

This affects c7n-mailer deployments when the PyJWT package is not properly included in the Lambda package dependencies.

## 📊 **Community Research Results**

### **Issue Status:** Open (as of October 2025)
- **Affected Versions:** c7n-mailer 0.6.55+ with Python 3.11+
- **Community Engagement:** Multiple affected users, active discussions
- **Platform Impact:** AWS Lambda deployments primarily

### **Community Resources:**
- **GitHub Issues:** 1.4k open issues, active issue tracking
- **Slack Community:** `communityinviter.com/apps/cloud-custodian/c7n-chat`
- **Documentation:** `cloudcustodian.io/docs/tools/c7n-mailer.html`

## ✅ **Community-Proven Solutions**

### **Solution 1: CORE_DEPS Modification (RECOMMENDED)**
**Source:** @harisfauzi on GitHub Issue #10282

**Description:** Add 'jwt' package to CORE_DEPS in c7n_mailer/deploy.py

**Implementation:**
```python
# Find: c7n_mailer/deploy.py in your Python installation
# Locate: CORE_DEPS = [
# Add: "jwt", after "jinja2",

CORE_DEPS = [
    # core deps
    "jinja2",
    "jwt",        # ← ADD THIS LINE
    "markupsafe",
    "yaml",
    # ... rest of dependencies
]
```

**Automated Fix Script:** `c7n/scripts/fix-core-deps.py` (created)

### **Solution 2: Version Rollback**
**Source:** @twstewart42 on GitHub Issue #10282

**Description:** Downgrade to c7n-mailer version 0.6.44

**Implementation:**
```bash
pip install c7n-mailer==0.6.44
```

**Note:** This is a temporary workaround that may lack newer features.

### **Solution 3: Architecture Compatibility**
**Source:** @kapilt (Cloud Custodian Collaborator)

**Key Point:** Lambda packaging requires Linux-compatible libraries

**Implementation:**
- Deploy from Linux environment matching Lambda architecture
- Use Docker containers for consistent packaging
- Avoid cross-platform deployment (Mac/Windows → AWS Lambda)

## 🔧 **Step-by-Step Resolution**

### **For Immediate Fix (Solution 1):**

1. **Locate c7n-mailer installation:**
```bash
python -c "import c7n_mailer.deploy; print(c7n_mailer.deploy.__file__)"
```

2. **Run the automated fix:**
```bash
python c7n/scripts/fix-core-deps.py
```

3. **Redeploy the mailer:**
```bash
c7n-mailer --config mailer.yml --update-lambda
```

4. **Verify the fix:**
```bash
aws lambda invoke --function-name cloud-custodian-mailer --payload '{}' response.json
```

### **For Long-term Stability:**

1. **Monitor the GitHub issue** for official fixes
2. **Consider contributing** to the upstream repository
3. **Document your environment** for future deployments

## 📈 **Success Metrics**

**Before Fix:**
- ❌ `Runtime.ImportModuleError: No module named 'jwt'`
- ❌ Lambda execution failures
- ❌ Notification system non-functional

**After Fix:**
- ✅ Lambda StatusCode: 200
- ✅ No import errors in Lambda logs
- ✅ Notification system operational
- ✅ Policy dry-runs complete successfully

## 🏆 **Verification Results**

**Environment:** Windows 11, Python 3.11, c7n-mailer 0.6.55+
**Test Date:** October 23, 2025
**Test Results:**
- ✅ CORE_DEPS modification successful
- ✅ Lambda deployment completed
- ✅ Function invocation: StatusCode 200
- ✅ Policy execution: count:0 time:1.66s (no errors)

## 🔗 **Community Contact**

### **For Ongoing Issues:**
1. **Slack:** Join at `communityinviter.com/apps/cloud-custodian/c7n-chat`
2. **GitHub:** Comment on Issue #10282
3. **Documentation:** Reference official docs at `cloudcustodian.io`

### **Contributing Back:**
- Share successful fixes in the GitHub issue
- Update documentation when solutions evolve
- Help other community members with similar issues

## 💡 **Lessons Learned**

1. **Community-driven solutions** often provide faster resolution than waiting for official patches
2. **Lambda packaging complexities** require careful dependency management
3. **Cross-platform deployment** considerations are critical for serverless applications
4. **Version compatibility** between Python, packages, and AWS Lambda runtime needs monitoring

## 📝 **Maintenance Notes**

- **Backup created:** `deploy.py.backup` in c7n-mailer installation directory
- **Revert command:** Copy backup over modified file if needed
- **Future updates:** Re-apply fix after c7n-mailer package updates
- **Monitor:** Watch GitHub issue #10282 for official resolution

---
*This document is based on active community research and proven solutions from the Cloud Custodian GitHub repository and community forums.*