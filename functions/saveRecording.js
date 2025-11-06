// functions/saveRecording.js
// Node wrapper to validate/export media using the project verifier.
// Usage (from project root):
//   node functions/saveRecording.js assets_pub/VEI_intro_main_10s_1080p_v1.mp4
// Or programmatically: require('./functions/saveRecording').verify(["assets_pub/*.mp4"])

const { execFile, exec } = require('child_process');
const { promisify } = require('util');
const path = require('path');
const fs = require('fs');

const execFileAsync = promisify(execFile);
const execAsync = promisify(exec);

const PROJECT_ROOT = path.resolve(__dirname, '..');
const VERIFY = path.join(PROJECT_ROOT, 'tools', 'verify_assets.sh');

function exists(p){ try { fs.accessSync(p); return true; } catch { return false; } }

async function ensureVerifier(){
  if(!exists(VERIFY)){
    throw new Error(`Verifier not found at ${VERIFY}. Move your verify_assets.sh into tools/ then chmod +x.`);
  }
  // make sure it's executable
  await execAsync(`chmod +x "${VERIFY}"`).catch(()=>{});
}

async function verify(inputs){
  await ensureVerifier();
  if(!Array.isArray(inputs) || inputs.length === 0){
    throw new Error('Pass at least one file. Example: node functions/saveRecording.js assets_pub/*');
  }
  const args = inputs;
  try {
    const { stdout, stderr } = await execFileAsync(VERIFY, args, { cwd: PROJECT_ROOT });
    process.stdout.write(stdout);
    if(stderr) process.stderr.write(stderr);
    return 0;
  } catch (err){
    if (err.stdout) process.stdout.write(err.stdout);
    if (err.stderr) process.stderr.write(err.stderr);
    // non‑zero exit indicates validation failures; bubble up the code
    return typeof err.code === 'number' ? err.code : 1;
  }
}

// CLI entry
if (require.main === module){
  const args = process.argv.slice(2);
  verify(args).then(code => process.exit(code));
}

module.exports = { verify };
