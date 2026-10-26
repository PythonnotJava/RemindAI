import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const schemasDir = path.resolve(__dirname, '../../schemas');

let validators = null;

/** Reason why schema validation is unavailable (null when it works). */
let schemaValidationDisabledReason = null;

try {
  const { default: Ajv2020 } = await import('ajv/dist/2020.js');
  const ajv = new Ajv2020({ allErrors: true, strict: true });
  const commonPath = path.join(schemasDir, 'common.schema.json');
  if (fs.existsSync(commonPath)) {
    ajv.addSchema(JSON.parse(fs.readFileSync(commonPath, 'utf8')));
  }
  validators = {};
  for (const type of ['workflow', 'sequence', 'dataflow', 'lifecycle', 'architecture']) {
    const schema = JSON.parse(fs.readFileSync(path.join(schemasDir, `${type}.schema.json`), 'utf8'));
    validators[type] = ajv.compile(schema);
  }
} catch (err) {
  if (err && err.code === 'ERR_MODULE_NOT_FOUND') {
    // 以前这里只打一行 warn 就继续渲染，产物看上去"通过校验"，
    // 实际上 type 枚举、多余字段、必填项一条都没查过——这是最坏的一种失败：
    // 静默降级的校验比没有校验更误导人。现在改为：
    //   1) stderr 打一个醒目横幅（不污染 stdout 的"产物路径"契约）；
    //   2) 支持 ARCHIFY_STRICT=1 直接失败（CI 或要求严格校验时用）；
    //   3) validateSchema 每次调用仍会返回"已跳过"，渲染层的几何检查照旧。
    schemaValidationDisabledReason = String(err.message || err);
    const lines = [
      '',
      '════════════════════════════════════════════════════════════',
      ' archify: ⚠  JSON-SCHEMA VALIDATION IS DISABLED (ajv not found)',
      `   reason : ${schemaValidationDisabledReason}`,
      `   schemas: ${schemasDir}`,
      '   effect : type enums / required fields / extra keys are NOT checked.',
      '            renderer layout checks (overlap, label width) still run.',
      '   fix    : cd into the archify skill folder and run  npm install',
      '   strict : set ARCHIFY_STRICT=1 to turn this into a hard failure',
      '════════════════════════════════════════════════════════════',
      '',
    ];
    console.error(lines.join('\n'));
    if (process.env.ARCHIFY_STRICT === '1') {
      throw new Error(
        'archify: ajv missing and ARCHIFY_STRICT=1 — run "npm install" in the skill folder.'
      );
    }
  } else {
    throw err;
  }
}

/** True when JSON-schema validation is actually active. */
export function isSchemaValidationEnabled() {
  return validators !== null;
}

/** Human-readable reason when validation is disabled, else null. */
export function schemaValidationNotice() {
  return schemaValidationDisabledReason;
}

// "/nodes/3/label" reads much better as "/nodes/3 (id: "router") /label" for the
// LLM fixing the JSON; resolve the nearest enclosing element's id or label.
function annotatePath(instancePath, data) {
  if (!instancePath) return '/';
  let node = data;
  let hint = null;
  for (const seg of instancePath.split('/').slice(1)) {
    if (node == null || typeof node !== 'object') break;
    node = node[/^\d+$/.test(seg) ? Number(seg) : seg];
    if (node && typeof node === 'object' && !Array.isArray(node)) {
      const tag = node.id ?? node.label;
      if (tag != null) hint = String(tag);
    }
  }
  return hint != null ? `${instancePath} (id/label: ${JSON.stringify(hint)})` : instancePath;
}

function formatErrors(errors, data) {
  return errors.map((e) => {
    const where = annotatePath(e.instancePath, data);
    const detail = e.params && Object.keys(e.params).length
      ? ' ' + JSON.stringify(e.params)
      : '';
    return `  ${where} ${e.message}${detail}`;
  }).join('\n');
}

export function validateSchema(diagramType, data) {
  if (!validators) {
    // 明确"跳过"而不是静默 return：每次渲染都在 stderr 留一行，
    // 方便在日志/终端里一眼看出这次产物其实没经过 schema 校验。
    console.error(
      `archify: schema validation SKIPPED for "${diagramType}" `
      + '(ajv missing — run "npm install" in the skill folder)'
    );
    return;
  }
  const validate = validators[diagramType];
  if (!validate) {
    throw new Error(`validateSchema: unknown diagram type "${diagramType}"`);
  }
  if (!validate(data)) {
    throw new Error(
      `${diagramType} schema validation failed:\n${formatErrors(validate.errors, data)}`
    );
  }
}
