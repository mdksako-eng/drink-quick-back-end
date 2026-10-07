// backend/tests/campay.test.js
// The CamerPay adapter: request shape, typed errors, the sandbox gate and the
// webhook signature recipes. No network — fetch is injected.
const crypto = require('crypto');
const campay = require('../utils/campay');

/** A fake fetch returning a fixed status + JSON body, recording the call. */
function jsonFetch(status, body) {
  const calls = [];
  const impl = async (url, options) => {
    calls.push({ url, options });
    return {
      ok: status >= 200 && status < 300,
      status,
      json: async () => body,
    };
  };
  impl.calls = calls;
  return impl;
}

const BASE_ARGS = {
  token: 'test-token',
  amount: 5000,
  merchantInvoiceId: 'FACT-001',
  callbackUrl: 'https://app.example/webhooks/campay',
  returnUrl: 'https://app.example/merci',
};

describe('token mode is unknowable from the token itself', () => {
  test('keyMode reports the account, not live/test', () => {
    expect(campay.keyMode()).toBe('account');
    expect(campay.canVerifyKeyMode()).toBe(false);
    expect(campay.isLive()).toBe(false);
  });

  test('status() exposes flags without pretending to know the mode', () => {
    const s = campay.status();
    expect(s.modeVerifiable).toBe(false);
    expect(s.mode).toBe('account');
    expect(typeof s.baseUrl).toBe('string');
  });

  test('hasToken validates the per-company credential', () => {
    expect(campay.hasToken('2|abc')).toBe(true);
    expect(campay.hasToken('   ')).toBe(false);
    expect(campay.hasToken(undefined)).toBe(false);
  });
});

describe('input helpers', () => {
  test('normalizePhone accepts the formats the dashboard and staff produce', () => {
    expect(campay.normalizePhone('+237 690 00 00 00')).toBe('237690000000');
    expect(campay.normalizePhone('690000000')).toBe('237690000000');
    expect(campay.normalizePhone('237690000000')).toBe('237690000000');
    expect(campay.normalizePhone('')).toBe('');
    expect(campay.normalizePhone(null)).toBe('');
  });

  test('invoiceId is capped at the documented 100 characters', () => {
    expect(campay.invoiceId('INV-1')).toBe('INV-1');
    expect(campay.invoiceId('x'.repeat(150))).toHaveLength(100);
  });

  test('isHttpsUrl refuses http and junk, because CamerPay blocks non-https', () => {
    expect(campay.isHttpsUrl('https://app.example/hook')).toBe(true);
    expect(campay.isHttpsUrl('http://app.example/hook')).toBe(false);
    expect(campay.isHttpsUrl('not-a-url')).toBe(false);
    expect(campay.isHttpsUrl('')).toBe(false);
  });
});

describe('initiatePayment', () => {
  test('POSTs the documented body to /payment/initiate with Bearer auth', async () => {
    const fetchImpl = jsonFetch(201, {
      success: true,
      transaction_uuid: 'uuid-1',
      status: 'pending',
      pay_url: 'https://camerpay.biz/pay/uuid-1',
      redirect_url: 'https://camerpay.biz/pay/uuid-1',
    });

    const res = await campay.initiatePayment({
      ...BASE_ARGS,
      paymentMethod: 'orange_money',
      customerPhone: '+237 690 00 00 00',
      customerEmail: 'client@example.com',
      customerName: 'Aicha',
      fetchImpl,
    });

    const { url, options } = fetchImpl.calls[0];
    expect(url).toBe('https://camerpay.biz/api/payment/initiate');
    expect(options.method).toBe('POST');
    expect(options.headers.Authorization).toBe('Bearer test-token');

    const body = JSON.parse(options.body);
    expect(body).toEqual({
      amount: 5000,
      currency: 'XAF',
      merchant_invoice_id: 'FACT-001',
      merchant_callback_url: 'https://app.example/webhooks/campay',
      merchant_return_url: 'https://app.example/merci',
      source: 'drinkquickcal',
      payment_method: 'orange_money',
      customer_phone: '237690000000',
      customer_email: 'client@example.com',
      customer_name: 'Aicha',
      idempotency_key: 'FACT-001',
    });

    expect(res.transactionUuid).toBe('uuid-1');
    expect(res.status).toBe('pending');
    expect(res.payUrl).toBe('https://camerpay.biz/pay/uuid-1');
    expect(res.replayed).toBe(false);
    expect(res.httpStatus).toBe(201);
  });

  test('an explicit idempotency key and source are honoured', async () => {
    const fetchImpl = jsonFetch(201, { success: true, transaction_uuid: 'u', pay_url: 'https://p' });
    await campay.initiatePayment({
      ...BASE_ARGS, idempotencyKey: 'order-42', source: 'drinkquickcal-pos', fetchImpl,
    });
    const body = JSON.parse(fetchImpl.calls[0].options.body);
    expect(body.idempotency_key).toBe('order-42');
    expect(body.source).toBe('drinkquickcal-pos');
  });

  test('HTTP 200 means CamerPay replayed an existing transaction', async () => {
    const fetchImpl = jsonFetch(200, { success: true, transaction_uuid: 'u-old', pay_url: 'https://p' });
    const res = await campay.initiatePayment({ ...BASE_ARGS, fetchImpl });
    expect(res.replayed).toBe(true);
    expect(res.transactionUuid).toBe('u-old');
  });
});
describe('initiatePayment validation', () => {
  test('rejects a bad amount, a non-XAF currency and a missing invoice id', async () => {
    const fetchImpl = jsonFetch(201, {});
    await expect(campay.initiatePayment({ ...BASE_ARGS, amount: 0, fetchImpl }))
      .rejects.toThrow(/positive number/);
    await expect(campay.initiatePayment({ ...BASE_ARGS, currency: 'USD', fetchImpl }))
      .rejects.toThrow(/only accepts XAF/);
    await expect(campay.initiatePayment({ ...BASE_ARGS, merchantInvoiceId: '', fetchImpl }))
      .rejects.toThrow(/merchant_invoice_id is required/);
    expect(fetchImpl.calls).toHaveLength(0);
  });

  test('rejects an unknown payment method', async () => {
    await expect(campay.initiatePayment({
      ...BASE_ARGS, paymentMethod: 'bitcoin', fetchImpl: jsonFetch(201, {}),
    })).rejects.toThrow(/Unsupported CamerPay payment method/);
  });

  test('rejects http callbacks before touching the network', async () => {
    const fetchImpl = jsonFetch(201, {});
    await expect(campay.initiatePayment({
      ...BASE_ARGS, callbackUrl: 'http://insecure.example/hook', fetchImpl,
    })).rejects.toThrow(/https callback/);
    expect(fetchImpl.calls).toHaveLength(0);
  });

  test('enforces the per-method provider limits locally', async () => {
    await expect(campay.initiatePayment({
      ...BASE_ARGS, amount: 50, paymentMethod: 'orange_money', fetchImpl: jsonFetch(201, {}),
    })).rejects.toThrow(/outside orange_money limits/);
    await expect(campay.initiatePayment({
      ...BASE_ARGS, amount: 250, paymentMethod: 'stripe', fetchImpl: jsonFetch(201, {}),
    })).rejects.toThrow(/outside stripe limits/);
  });
});

describe('typed errors', () => {
  test('surfaces the KYC / quota 402 with its next action', async () => {
    const fetchImpl = jsonFetch(402, {
      success: false,
      error: 'kyc_tier_volume_exceeded',
      message: 'Votre niveau KYC-1 Basique plafonne votre volume mensuel a 200 000 XAF.',
      kyc_tier: 1,
      monthly_limit: 200000,
      current_volume: 195000,
      remaining: 5000,
      next_action: 'Fournissez votre attestation NIU pour passer en KYC-2 (1 000 000 XAF/mois).',
      upgrade_url: 'https://camerpay.biz/client/kyc',
    });

    let error;
    try {
      await campay.initiatePayment({ ...BASE_ARGS, fetchImpl });
    } catch (e) {
      error = e;
    }
    expect(error).toBeInstanceOf(campay.CampayError);
    expect(error.name).toBe('CampayError');
    expect(error.status).toBe(402);
    expect(error.code).toBe('kyc_tier_volume_exceeded');
    expect(error.payload.remaining).toBe(5000);
    expect(error.payload.next_action).toMatch(/NIU/);
    expect(error.payload.upgrade_url).toBe('https://camerpay.biz/client/kyc');
  });

  test('surfaces 429 so callers can back off', async () => {
    const fetchImpl = jsonFetch(429, { message: 'Too Many Requests' });
    await expect(campay.initiatePayment({ ...BASE_ARGS, fetchImpl }))
      .rejects.toMatchObject({ status: 429 });
  });

  test('a network failure becomes status 0, never a fake success', async () => {
    const fetchImpl = async () => { throw new Error('socket hang up'); };
    let error;
    try {
      await campay.initiatePayment({ ...BASE_ARGS, fetchImpl });
    } catch (e) {
      error = e;
    }
    expect(error.status).toBe(0);
    expect(error.code).toBe('network_error');
  });
});
describe('getPaymentStatus and the activation gate', () => {
  test('parses the documented transaction payload', async () => {
    const fetchImpl = jsonFetch(200, {
      success: true,
      transaction: {
        uuid: 'u1',
        status: 'completed',
        amount: 5000,
        currency: 'XAF',
        payment_method: 'orange_money',
        customer_phone: '+237 690 00 00 00',
        merchant_invoice_id: 'FACT-001',
        is_sandbox: false,
        paid_at: '2026-06-05T14:23:11.000000Z',
        created_at: '2026-06-05T14:22:48.000000Z',
      },
    });
    const tx = await campay.getPaymentStatus('u1', { token: 't', fetchImpl });
    expect(fetchImpl.calls[0].url).toBe('https://camerpay.biz/api/payment/u1/status');
    expect(tx).toMatchObject({
      uuid: 'u1', status: 'completed', amount: 5000, isSandbox: false,
      merchantInvoiceId: 'FACT-001', paymentMethod: 'orange_money',
    });
  });

  test('returns null without a uuid or without a transaction', async () => {
    expect(await campay.getPaymentStatus('', {})).toBeNull();
    expect(await campay.getPaymentStatus('u1', { fetchImpl: jsonFetch(200, { success: true }) }))
      .toBeNull();
  });

  test('the activation gate needs completed AND real money', () => {
    expect(campay.isVerifiablePaidTransaction({ status: 'completed', isSandbox: false })).toBe(true);
    expect(campay.isVerifiablePaidTransaction({ status: 'completed', is_sandbox: false })).toBe(true);
    expect(campay.isVerifiablePaidTransaction({ status: 'completed', isSandbox: true })).toBe(false);
    expect(campay.isVerifiablePaidTransaction({ status: 'pending', isSandbox: false })).toBe(false);
    expect(campay.isVerifiablePaidTransaction({ status: 'refunded', isSandbox: false })).toBe(false);
    expect(campay.isVerifiablePaidTransaction(null)).toBe(false);
  });

  test('statuses map onto our canonical set', () => {
    expect(campay.normalizeStatus('completed')).toBe('completed');
    expect(campay.normalizeStatus('processing')).toBe('pending');
    expect(campay.normalizeStatus('cancelled')).toBe('cancelled');
    expect(campay.normalizeStatus('refunded')).toBe('refunded');
    expect(campay.normalizeStatus('something-new')).toBe('pending');
  });
});

describe('webhook signature (HMAC-SHA256 hex)', () => {
  const secret = 'whsec_unit_test';
  const body = 'uuid=5add2319&invoice_id=FACT-001&status=completed&amount=5000';
  const sig = (value) => crypto.createHmac('sha256', secret).update(value).digest('hex');

  test('accepts the raw-body recipe CamerPay documents', () => {
    expect(campay.verifyWebhookSignature(body, sig(body), secret, 'raw')).toBe(true);
    expect(campay.verifyWebhookSignature(body, sig(body), secret)).toBe(true);
    expect(campay.matchSignatureMode(body, sig(body), secret)).toBe('raw');
  });

  test('accepts the body that carries its own signature field', () => {
    const withSig = `${body}&signature=${sig(body)}`;
    expect(campay.verifyWebhookSignature(withSig, sig(body), secret, 'without_signature')).toBe(true);
    expect(campay.matchSignatureMode(withSig, sig(body), secret)).toBe('without_signature');
  });

  test('the header value and the body field are interchangeable', () => {
    const withSig = `${body}&signature=${sig(body)}`;
    expect(campay.verifyWebhookSignature(withSig, campay.parseWebhookBody(withSig).signature, secret))
      .toBe(true);
  });

  test('the hex digest is compared case-insensitively', () => {
    expect(campay.verifyWebhookSignature(body, sig(body).toUpperCase(), secret)).toBe(true);
  });

  test('rejects a wrong signature, a missing secret and a short value', () => {
    expect(campay.verifyWebhookSignature(body, 'deadbeef', secret)).toBe(false);
    expect(campay.verifyWebhookSignature(body, sig(body), '')).toBe(false);
    expect(campay.verifyWebhookSignature(body, 'abc', secret)).toBe(false);
    expect(campay.verifyWebhookSignature(body, '', secret)).toBe(false);
  });

  test('a tampered body fails', () => {
    const tampered = body.replace('amount=5000', 'amount=500000');
    expect(campay.verifyWebhookSignature(tampered, sig(body), secret)).toBe(false);
  });

  test('timingSafeEquals never throws on a length mismatch', () => {
    expect(campay.timingSafeEquals('a', 'bb')).toBe(false);
    expect(campay.timingSafeEquals('', '')).toBe(false);
    expect(campay.timingSafeEquals('same', 'same')).toBe(true);
  });
});
describe('webhook body and failure classification', () => {
  test('parses the form-encoded body, including a failed payment', () => {
    const raw = 'uuid=5add2319-f71b&invoice_id=FACT-001&status=failed&amount=10000.00'
      + '&failure_reason=Le+solde+du+compte+du+payeur+est+insuffisant&failure_code=60019&signature=abc';
    const fields = campay.parseWebhookBody(raw);
    expect(fields.status).toBe('failed');
    expect(fields.amount).toBe('10000.00');
    expect(fields.failure_code).toBe('60019');
    expect(fields.failure_reason).toContain('insuffisant');
    expect(fields.signature).toBe('abc');
  });

  test('empty and junk bodies parse to an empty object', () => {
    expect(campay.parseWebhookBody('')).toEqual({});
    expect(campay.parseWebhookBody(null)).toEqual({});
  });

  test('classifies payer vs provider failures', () => {
    expect(campay.classifyFailure('60019')).toBe('payer');
    expect(campay.classifyFailure('card_declined')).toBe('payer');
    expect(campay.classifyFailure('60030')).toBe('provider');
    expect(campay.classifyFailure('INTERNAL_ERROR')).toBe('provider');
    expect(campay.classifyFailure('who_knows')).toBe('unknown');
    expect(campay.classifyFailure(null)).toBe('unknown');
  });

  test('canonicalPayload drops the signature and sorts the rest', () => {
    expect(campay.canonicalPayload({ status: 'completed', amount: '5000', signature: 'x' }))
      .toBe('amount=5000&status=completed');
  });
});

describe('refundPayment', () => {
  test('posts the reason and reports success', async () => {
    const fetchImpl = jsonFetch(200, { success: true });
    const res = await campay.refundPayment('uuid-1', { reason: 'Geste commercial', fetchImpl });
    expect(fetchImpl.calls[0].url).toBe('https://camerpay.biz/api/payment/uuid-1/refund');
    expect(JSON.parse(fetchImpl.calls[0].options.body)).toEqual({ reason: 'Geste commercial' });
    expect(res.success).toBe(true);
  });

  test('requires a uuid', async () => {
    await expect(campay.refundPayment('', {})).rejects.toThrow(/needs a transaction uuid/);
  });
});



