// Component cache and compiler provenance for the canonical web builder.
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import crypto from 'node:crypto';
import {execFileSync, spawn} from 'node:child_process';
import {fileURLToPath, pathToFileURL} from 'node:url';

const schema = 1;
const sha = value => crypto.createHash('sha256').update(value).digest('hex');
const jsonHash = value => sha(JSON.stringify(value));
const read = file => JSON.parse(fs.readFileSync(file, 'utf8'));
const run = (cwd, command, args) => execFileSync(command, args, {cwd, encoding:'utf8', maxBuffer:64*1024*1024}).trim();
const source = root => run(root, 'git', ['rev-parse', 'HEAD']);
const cacheHome = () => path.join(process.env.XDG_CACHE_HOME || path.join(os.homedir(), '.cache'), 'festapp/web-build');

export function dependencyDigest(directory,normalizeInstallerMetadata=false) {
  const hash=crypto.createHash('sha256'), visited=new Set();
  const dependencyRoot=fs.realpathSync(directory);
  function visit(file, relative) {
    const real=fs.realpathSync(file), stat=fs.statSync(file);
    hash.update(JSON.stringify([relative,stat.mode & 0o777]));
    if (visited.has(real)) {hash.update(JSON.stringify(['alias',path.relative(dependencyRoot,real)]));return;}
    visited.add(real);
    if(stat.isDirectory()) {
      for(const name of fs.readdirSync(file).sort()) {
        // Vite creates and removes bundled config files here on first build.
        // Their inputs are the tracked Vite config and installed dependencies.
        if(normalizeInstallerMetadata && relative==='' && name==='.vite-temp')continue;
        if(!['.git','.dart_tool','__pycache__'].includes(name))visit(path.join(file,name),`${relative}/${name}`);
      }
    } else if(stat.isFile()) {
      const bytes=fs.readFileSync(file);
      const timestamp=relative==='/.modules.yaml'?'prunedAt':relative==='/.pnpm-workspace-state-v1.json'?'lastValidatedTimestamp':null;
      if(normalizeInstallerMetadata && timestamp) {
        // pnpm 11.24 writes these timestamps on every frozen install. All
        // dependency bytes, link topology and remaining metadata still count.
        const metadata=JSON.parse(bytes);delete metadata[timestamp];hash.update(JSON.stringify(metadata));
      } else hash.update(bytes);
    }
    else throw new Error('Unsupported dependency input');
  }
  visit(directory,'');return hash.digest('hex');
}

export function inventory(root, excluded = new Set(), prefix = '') {
  const result = [];
  for (const name of fs.readdirSync(path.join(root, prefix)).sort()) {
    if (excluded.has(name)) continue;
    const relative = prefix ? `${prefix}/${name}` : name;
    const file = path.join(root, relative);
    const stat = fs.lstatSync(file);
    if (stat.isSymbolicLink()) throw new Error(`Unsupported symlink in build inputs/output: ${relative}`);
    if (stat.isDirectory()) result.push(...inventory(root, excluded, relative));
    else if (stat.isFile()) result.push({path:relative, mode:stat.mode & 0o777, size:stat.size, hash:sha(fs.readFileSync(file))});
    else throw new Error(`Unsupported build file: ${relative}`);
  }
  return result;
}

function inputFiles(root,excluded,prefix='') {
  const files=[];
  for(const entry of fs.readdirSync(path.join(root,prefix),{withFileTypes:true})) {
    if(excluded.has(entry.name))continue;
    const relative=prefix?`${prefix}/${entry.name}`:entry.name;
    if(entry.isDirectory())files.push(...inputFiles(root,excluded,relative));
    else if(entry.isFile())files.push(relative);
    else throw new Error(`Unsupported build input: ${relative}`);
  }
  return files;
}

export function identity(root, target) {
  const conf = fs.readFileSync(path.join(root, 'automation/project.conf'), 'utf8');
  const value = key => (conf.match(new RegExp(`^${key}=(.*)$`, 'm'))?.[1] || '').trim().replace(/^['"]|['"]$/g, '');
  return {tenant:value('DOMAIN'), project:value('CLOUDFLARE_PROJECT_NAME'), organization:value('ORGANIZATION_ID'), target, version:value('VERSION')};
}

function compilerBytes(root,file,versionPackaging) {
  const bytes=fs.readFileSync(path.join(root,file));
  if(!versionPackaging)return bytes;
  // SDK 3.47.7 real builds +485/+486 produced identical main/deferred JS.
  // PackageInfoPlusWebPlugin reads version.json at runtime; native is unchanged.
  if(file==='pubspec.yaml')return bytes.toString().replace(/^version:[^\r\n]+/m,'version: <packaging>');
  if(file==='automation/project.conf')return bytes.toString().replace(/^VERSION=[^\r\n]+/m,'VERSION=<packaging>');
  if(file==='web/index.html')return bytes.toString().replace(/(window\.__FESTAPP_BUILD_VERSION__\s*=\s*)"[^"]*"/,'$1"<packaging>"');
  return bytes;
}

export function stampFlutterMetadata(root,output) {
  const version=identity(root,'static').version;
  const match=version.match(/^(\d+\.\d+\.\d+)\+(\d+)$/);
  if(!match)throw new Error('Invalid Flutter packaging version');
  const file=path.join(output,'version.json');
  const metadata=read(file);
  if(!metadata.app_name || !metadata.package_name)throw new Error('Unsupported Flutter version.json schema');
  metadata.version=match[1];metadata.build_number=match[2];
  fs.writeFileSync(file,JSON.stringify(metadata));
  const index=path.join(output,'index.html');
  const html=fs.readFileSync(index,'utf8');
  const marker=/(window\.__FESTAPP_BUILD_VERSION__\s*=\s*)"[^"]*"/g;
  if([...html.matchAll(marker)].length!==1)throw new Error('Unsupported Flutter HTML version marker');
  fs.writeFileSync(index,html.replace(marker,(_,prefix)=>`${prefix}"${version}"`));
  const bootstrap=path.join(output,'flutter_bootstrap.js');
  if(fs.existsSync(bootstrap)) {
    // Flutter emits Random().nextInt(1 << 32) here (SDK web.dart). The app
    // uses its own worker; retain the opaque cache-buster with stable release
    // identity so equal cold/warm releases have identical bootstrap bytes.
    const source=fs.readFileSync(bootstrap,'utf8');
    fs.writeFileSync(bootstrap,source.replace(/(\bserviceWorkerVersion:\s*)"[^"]*"/,(_,prefix)=>prefix+JSON.stringify(version.replace('+','-'))));
  }
}

// Actual SDK revision comes from the resolved package graph, not a version label.
export function toolchain(root,component='bundle') {
  const pnpm = run(root, 'pnpm', ['--version']);
  if (pnpm !== '11.24.0') throw new Error('pnpm 11.24.0 required');
  const tools={node:process.version,pnpm,platform:process.platform,arch:process.arch};
  if(component!=='flutter')tools.javascriptDependencies=dependencyDigest(path.join(root,'web_client/node_modules'),true);
  if(component==='vite')return tools;
  const packagesFile = path.join(root, '.dart_tool/package_config.json');
  const packages = read(packagesFile);
  const flutter = packages.packages.find(p => p.name === 'flutter');
  if (!flutter) throw new Error('Flutter package graph missing; rebuild after dependency preparation');
  const flutterRoot = fileURLToPath(new URL(flutter.rootUri, pathToFileURL(packagesFile)));
  const sdk = path.resolve(flutterRoot, '../..');
  const sdkVersion = read(path.join(sdk, 'bin/cache/flutter.version.json'));
  return {...tools,sdkVersion,
    sdkRevision:run(sdk,'git',['rev-parse','HEAD']),
    compiler: ['bin/cache/flutter_tools.snapshot','bin/cache/dart-sdk/version','bin/cache/dart-sdk/bin/snapshots/dart2js_aot.dart.snapshot'].map(file=>[file,sha(fs.readFileSync(path.join(sdk,file)))]),
    // Hash resolved dependency bytes, including external path/pub packages.
    dependencies: packages.packages.map(p => {
      const directory = fileURLToPath(new URL(p.rootUri, pathToFileURL(packagesFile)));
      if (directory === root || directory.startsWith(root + path.sep)) return [p.name, 'repository:'+path.relative(root,directory)];
      return [p.name, dependencyDigest(directory)];
    }).sort((a,b) => a[0].localeCompare(b[0]))};
}

export function fingerprint(root, component, target, tools = toolchain(root,component)) {
  const manifest = read(path.join(root, 'automation/web_build_inputs.json'));
  const versionPackaging=component==='flutter' && tools.sdkRevision===manifest.flutterVersionPackaging.sdkRevision &&
    equal(tools.compiler,manifest.flutterVersionPackaging.compiler);
  const excluded = new Set(manifest.excludedDirectories);
  const paths = new Set(run(root, 'git', ['ls-files', '-z', '--cached', '--others', '--exclude-standard']).split('\0').filter(Boolean));
  for (const directory of manifest.environmentRoots) {
    for (const name of fs.readdirSync(path.join(root,directory))) if (/^\.env(?:\.|$)/.test(name)) paths.add(path.posix.join(directory,name));
  }
  // Git ignores generated assets. They remain real compiler inputs.
  for (const directory of manifest.generatedRoots) {
    if (fs.existsSync(path.join(root, directory))) for (const file of inputFiles(path.join(root, directory), excluded)) paths.add(`${directory}/${file}`);
  }
  const matches = (file, entries) => entries.some(p => p.endsWith('/') ? file.startsWith(p) : file === p);
  const inputs = [...paths].sort().filter(file => {
    if (manifest.excludedPrefixes.some(prefix => file.startsWith(prefix))) return false;
    if (file.split('/').some(p => excluded.has(p))) return false;
    if (component !== 'bundle' && matches(file, manifest.packagingOnly)) return false;
    if (component === 'flutter' && matches(file, manifest.viteOnly)) return false;
    if (component === 'vite' && matches(file, manifest.flutterOnly)) return false;
    return true; // Unknown inputs conservatively invalidate both components.
  }).map(file => {
    const absolute = path.join(root, file);
    if (!fs.existsSync(absolute)) return {path:file, missing:true};
    const stat = fs.lstatSync(absolute);
    if (stat.isSymbolicLink() || !stat.isFile()) throw new Error(`Unclassified build input: ${file}`);
    return {path:file, mode:stat.mode & 0o777, hash:sha(compilerBytes(root,file,versionPackaging))};
  });
  const environment = Object.fromEntries(Object.entries(process.env).filter(([name]) => name!=='FLUTTER_VERSION' && /^(VITE_|DART_|FLUTTER_|NODE_OPTIONS$|NODE_ENV$|FESTAPP_OCCASION_SETUP$)/.test(name)).sort());
  const tenant=identity(root,target);
  if(versionPackaging)tenant.version='<packaging>';
  const compilerTools={...tools};
  if(component==='flutter')delete compilerTools.javascriptDependencies;
  if(component==='vite')for(const key of ['sdkVersion','sdkRevision','compiler','dependencies'])delete compilerTools[key];
  const context = {schema, component, identity:tenant, tools:compilerTools, manifest, environmentHash:jsonHash(environment)};
  return {key:jsonHash({context,inputs}), context};
}

function equal(a,b) { return JSON.stringify(a) === JSON.stringify(b); }
function validComponent(metadata,key,tools) {
  return metadata?.schema===schema && metadata.key===key && /^[a-f0-9]{40}$/.test(metadata.source || '') &&
    metadata.tools && typeof metadata.tools==='object' && (!tools || equal(metadata.tools,tools)) &&
    Array.isArray(metadata.files) && metadata.files.length>0 && metadata.outputHash===jsonHash(metadata.files);
}
function loadEntry(directory, key,tools) {
  try {
    const metadata = read(path.join(directory, 'entry.json'));
    if (!validComponent(metadata,key,tools) || !equal(metadata.files, inventory(path.join(directory,'files')))) return null;
    return metadata;
  } catch { return null; }
}

// Dead local owners are recoverable. Live locks never expire underneath a build.
async function lock(directory) {
  fs.mkdirSync(path.dirname(directory), {recursive:true});
  for (let attempt=0; attempt<600; attempt++) {
    try {
      fs.mkdirSync(directory);
      fs.writeFileSync(path.join(directory,'owner.json'), JSON.stringify({pid:process.pid, host:os.hostname()}));
      return () => fs.rmSync(directory,{recursive:true,force:true});
    } catch (error) {
      if (error.code !== 'EEXIST') throw error;
      let recovery = false;
      try {
        fs.mkdirSync(directory+'.recovery');
        recovery = true;
        const owner = read(path.join(directory,'owner.json'));
        if (owner.host === os.hostname()) {
          try { process.kill(owner.pid,0); } catch (e) {
            if (e.code === 'ESRCH') {
              let childAlive = false;
              if (owner.childPid) { try {process.kill(owner.childPid,0);childAlive=true;} catch {} }
              if (!childAlive) { fs.rmSync(directory,{recursive:true,force:true}); continue; }
            }
          }
        }
      } catch { /* Incomplete owner creation: wait, never steal an active lock. */ }
      finally { if (recovery) fs.rmSync(directory+'.recovery',{recursive:true,force:true}); }
      await new Promise(resolve => setTimeout(resolve,1000));
    }
  }
  throw new Error('Build cache lock timed out; inspect interrupted lock owner');
}

export async function componentBuild({root, component, target, output, command, tools, home=cacheHome(), enabled=process.env.FESTAPP_WEB_BUILD_CACHE !== 'off'}) {
  const before = fingerprint(root,component,target,tools);
  const directory = path.join(home, component, before.key);
  const unlockWorkstation = component === 'flutter' ? await lock(path.join(home,'flutter-workstation.lock')) : () => {};
  let unlock = () => {};
  try {
    unlock = await lock(directory+'.lock');
    const hit = enabled && loadEntry(directory,before.key,before.context.tools);
    if (hit) {
      fs.rmSync(output,{recursive:true,force:true});
      fs.cpSync(path.join(directory,'files'),output,{recursive:true});
      console.error(`build-cache component=${component} result=hit key=${before.key}`);
      return hit;
    }
    const reason=!enabled?'disabled':fs.existsSync(directory)?'invalid-entry':'inputs-or-first-build';
    console.error(`build-cache component=${component} result=miss reason=${reason} key=${before.key}`);
    fs.rmSync(output,{recursive:true,force:true});
    const compilationSource=source(root);
    await new Promise((resolve,reject) => {
      const child = spawn(command[0],command.slice(1),{cwd:root,stdio:'inherit'});
      for (const ownerDirectory of [directory+'.lock', ...(component === 'flutter' ? [path.join(home,'flutter-workstation.lock')] : [])]) {
        fs.writeFileSync(path.join(ownerDirectory,'owner.json'),JSON.stringify({pid:process.pid,host:os.hostname(),childPid:child.pid}));
      }
      child.on('error',reject);
      child.on('exit',(code,signal) => code === 0 ? resolve() : reject(new Error(`${component} compilation failed (${signal || code})`)));
    });
    const after = fingerprint(root,component,target,tools);
    if (before.key !== after.key) throw new Error(`${component} inputs changed during compilation; rebuild required`);
    const files=inventory(output);
    const metadata = {schema,key:before.key, outputHash:jsonHash(files), source:compilationSource, files, tools:before.context.tools};
    if (!metadata.files.length) throw new Error('Empty component output');
    if (enabled) {
      const temporary = fs.mkdtempSync(directory+'.tmp-');
      try {
        fs.cpSync(output,path.join(temporary,'files'),{recursive:true});
        fs.writeFileSync(path.join(temporary,'entry.json'),JSON.stringify(metadata));
        fs.rmSync(directory,{recursive:true,force:true});
        fs.renameSync(temporary,directory);
      } finally { fs.rmSync(temporary,{recursive:true,force:true}); }
    }
    return metadata;
  } finally { unlock(); unlockWorkstation(); }
}

// Bounded retention, never touching locked entries, other worktrees or staging.
export function pruneCache(home=cacheHome(), keep=12, maxAgeDays=30) {
  for (const component of ['flutter','vite']) {
    const parent = path.join(home,component);
    if (!fs.existsSync(parent)) continue;
    const names=fs.readdirSync(parent);
    const entries = names.filter(n => /^[a-f0-9]{64}$/.test(n))
      .flatMap(name => {
        try {return [{name,time:fs.statSync(path.join(parent,name)).mtimeMs}];}
        catch(error) {if(error.code==='ENOENT')return [];throw error;}
      }).sort((a,b) => b.time-a.time);
    const expired=entries.filter((entry,index)=>index >= keep || Date.now()-entry.time >= maxAgeDays*86400000);
    for(const name of names.filter(n=>/^[a-f0-9]{64}\.tmp-/.test(n))) {
      try {if(Date.now()-fs.statSync(path.join(parent,name)).mtimeMs >= maxAgeDays*86400000)expired.push({name});}
      catch(error) {if(error.code!=='ENOENT')throw error;}
    }
    for (const entry of expired) {
      const directory = path.join(parent,entry.name);
      const lockPath=path.join(parent,entry.name.slice(0,64))+'.lock';
      try { fs.mkdirSync(lockPath); } catch (e) { if(e.code==='EEXIST') continue; throw e; }
      fs.writeFileSync(path.join(lockPath,'owner.json'),JSON.stringify({pid:process.pid,host:os.hostname()}));
      try { fs.rmSync(directory,{recursive:true,force:true}); }
      finally { fs.rmSync(lockPath,{recursive:true,force:true}); }
    }
  }
}

export function inputFingerprints(root,target,tools=toolchain(root)) {
  return Object.fromEntries(['flutter','vite','bundle'].map(c=>[c,fingerprint(root,c,target,tools).key]));
}

export function compilationProvenance(root,target,tools=toolchain(root)) {
  const result={components:{},inputFingerprints:inputFingerprints(root,target,tools)};
  for(const component of ['flutter','vite']) {
    const current=fingerprint(root,component,target,tools);
    const metadata=read(path.join(root,`build/web-components/${component}.json`));
    if(!validComponent(metadata,current.key,current.context.tools))throw new Error(`${component} inputs or compilation provenance invalid; rebuild required`);
    result.components[component]={key:metadata.key,outputHash:metadata.outputHash,source:metadata.source,toolchainHash:jsonHash(metadata.tools)};
  }
  return result;
}

async function main() {
  const [operation,component,target,...command] = process.argv.slice(2);
  const root = process.cwd();
  const output = path.join(root,'build/web');
  if (operation === 'component') {
    const policy=read(path.join(root,'automation/web_build_inputs.json'));
    let allowed=false;
    if(component==='flutter') {
      const setup=fs.readFileSync(path.join(root,'automation/project.conf'),'utf8').match(/^OCCASION_SETUP_ENABLED=(.*)$/m)?.[1];
      const expected=[...policy.flutterCommand,...(setup==='true'?['--dart-define=FESTAPP_OCCASION_SETUP=true']:[])];
      const start=command.indexOf('build');
      allowed=start>=0 && equal(command.slice(start),expected);
    } else if(component==='vite')allowed=equal(command,['bash','-c','cd web_client && '+policy.viteCommand.join(' ')]);
    if(!allowed)throw new Error('Unsupported compiler parameters; use the canonical web build orchestrator');
    const result = await componentBuild({root,component,target,output:path.join(root,component === 'flutter' ? 'build/web' : 'web_client/dist'),command});
    fs.mkdirSync(path.join(root,'build/web-components'),{recursive:true});
    fs.writeFileSync(path.join(root,`build/web-components/${component}.json`),JSON.stringify(result));
  } else if (operation === 'stamp-flutter') {
    stampFlutterMetadata(root,output);
  } else if (operation === 'fingerprints') {
    console.log(JSON.stringify(inputFingerprints(root,component)));
  } else if (operation === 'provenance') {
    console.log(JSON.stringify(compilationProvenance(root,component)));
    pruneCache();
  } else throw new Error('Usage: web_build_cache.mjs component <flutter|vite> <target> <command...> | fingerprints/provenance <target>');
}
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) main().catch(error => {console.error(error.message);process.exitCode=1;});
