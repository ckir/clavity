# Clavity Analytics & Telemetry Strategy

Architecture and specifications for privacy-conscious web analytics, attribution modeling, and client-side conversion instrumentation.

## 1. Core Privacy Philosophy

Clavity operates under strict developer privacy boundaries:
- **No Ingestion of Proprietary Data:** Never collect, transmit, or log user code, diffs, terminal outputs, prompts, or API keys.
- **Provider-Independent Architecture:** The website instrumentation uses an abstract event dispatcher (`ClavityAnalytics`) that can route to privacy-friendly providers (Plausible, PostHog, or custom endpoint) or no-op cleanly when unconfigured.
- **Cookie-Free & Zero-PII by Default:** Standard web metrics avoid tracking cookies and persistent cross-site device fingerprints.
- **Safe Fallback:** If analytics scripts fail to load, are blocked by ad-blockers, or are disabled, the website remains 100% functional.

## 2. Acquisition & Campaign Attribution (UTM Parameters)

Campaign links across social, email, and community channels must use standardized UTM tagging to identify inbound acquisition channels:

| Parameter | Recommended Format / Examples | Purpose |
|---|---|---|
| `utm_source` | `hackernews`, `reddit`, `x`, `linkedin`, `producthunt`, `github` | Referring platform |
| `utm_medium` | `social`, `community`, `article`, `newsletter` | Channel medium |
| `utm_campaign` | `beta-launch`, `show-hn`, `capstone-tutorial` | Marketing campaign |
| `utm_content` | `hero-cta`, `split-screen-video`, `text-link` | Specific creative / element |

The client-side script parses and preserves UTM parameters during session navigation to attribute beta form submissions accurately.

## 3. Standard Conversion Events Specification

The event abstraction interface enforces the following payload schema:

```typescript
interface AnalyticsEvent {
  name: string;
  properties?: Record<string, string | number | boolean>;
}
```

### Event Taxonomy

1. **`page_view`**
   - **Trigger:** Initial page load and history navigation.
   - **Properties:** `path`, `title`, `referrer`.
2. **`beta_cta_clicked`**
   - **Trigger:** User clicks on any primary or secondary beta CTA button.
   - **Properties:** `location` (e.g., `header`, `hero`, `banner`, `footer`), `target_url`.
3. **`github_clicked`**
   - **Trigger:** User clicks any outbound link pointing to the GitHub repository or release assets.
   - **Properties:** `target` (e.g., `repo_root`, `issues`, `discussions`, `releases`), `location`.
4. **`documentation_clicked`**
   - **Trigger:** User clicks a link navigating to documentation or guides.
   - **Properties:** `doc_name`, `doc_type` (`pdf`, `html`, `repo_md`).
5. **`product_page_viewed`**
   - **Trigger:** User navigates to a dedicated product subpage.
   - **Properties:** `product_name` (`bridge`, `agent-knowledge`, `shared-memory`, `review-relay`).
6. **`install_command_copied`**
   - **Trigger:** User clicks a "Copy" button on the terminal command list.
   - **Properties:** `command` (e.g. `claude plugin install clavity@clavity`).
7. **`beta_form_started`**
   - **Trigger:** User focuses or interacts with the first field of the beta interest form.
   - **Properties:** `form_id`.
8. **`beta_form_submitted`**
   - **Trigger:** Successful client-side validation and dispatch of the beta registration form.
   - **Properties:** `role_type` (`individual`, `team`, `enterprise`), `has_commercial_interest` (boolean). *(Note: Never include email addresses in analytics events).*
9. **`feedback_clicked`**
   - **Trigger:** User clicks outbound link to report issues or submit feedback.
   - **Properties:** `destination` (`github_issues`, `discussions`).

## 4. Consent & Regulatory Compliance

- **GDPR / ePrivacy Compliance:** Because the recommended analytics approach does not set non-essential cookies and collects no PII, cookie consent banners are avoided where permissible under legitimate interest guidance.
- **Explicit Form Consent:** The beta registration form includes an explicit privacy acknowledgement stating how the provided email address will be used (strictly for release updates and pilot research).
- **Data Retention:** Registration records should be purged within 12 months unless converted into an active commercial relationship or renewed by the participant.
