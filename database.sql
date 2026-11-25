-- HUDHUD SABA
-- المرحلة الأولى: تأسيس قاعدة البيانات
-- متوافق مع Supabase PostgreSQL

BEGIN;

-- 1. بيانات المستخدمين الأساسية
CREATE TABLE IF NOT EXISTS public.profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    full_name TEXT NOT NULL DEFAULT '',
    account_type TEXT NOT NULL DEFAULT 'customer'
        CHECK (account_type IN (
            'customer',
            'merchant',
            'logistics_provider',
            'courier'
        )),
    status TEXT NOT NULL DEFAULT 'pending'
        CHECK (status IN (
            'pending',
            'active',
            'suspended',
            'closed'
        )),
    preferred_language TEXT NOT NULL DEFAULT 'ar'
        CHECK (preferred_language IN ('ar', 'en')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 2. إنشاء بيانات المستخدم تلقائياً عند التسجيل
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    INSERT INTO public.profiles (id, full_name)
    VALUES (
        NEW.id,
        COALESCE(NEW.raw_user_meta_data ->> 'full_name', '')
    );
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

CREATE TRIGGER on_auth_user_created
AFTER INSERT ON auth.users
FOR EACH ROW
EXECUTE FUNCTION public.handle_new_user();

-- 3. بيانات العملاء
CREATE TABLE IF NOT EXISTS public.customer_profiles (
    user_id UUID PRIMARY KEY
        REFERENCES public.profiles(id) ON DELETE RESTRICT,
    display_name TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 4. بيانات التجار
CREATE TABLE IF NOT EXISTS public.merchant_profiles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    owner_user_id UUID NOT NULL UNIQUE
        REFERENCES public.profiles(id) ON DELETE RESTRICT,
    legal_name TEXT NOT NULL,
    public_name TEXT NOT NULL,
    registration_no TEXT,
    review_status TEXT NOT NULL DEFAULT 'pending'
        CHECK (review_status IN (
            'pending', 'approved', 'rejected'
        )),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 5. بيانات مكاتب الخدمات اللوجستية
CREATE TABLE IF NOT EXISTS public.logistics_offices (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    owner_user_id UUID NOT NULL UNIQUE
        REFERENCES public.profiles(id) ON DELETE RESTRICT,
    legal_name TEXT NOT NULL,
    public_name TEXT NOT NULL,
    registration_no TEXT,
    review_status TEXT NOT NULL DEFAULT 'pending'
        CHECK (review_status IN (
            'pending', 'approved', 'rejected'
        )),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 6. سجل تدقيق العمليات
CREATE TABLE IF NOT EXISTS public.audit_events (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    actor_user_id UUID REFERENCES public.profiles(id)
        ON DELETE RESTRICT,
    event_type TEXT NOT NULL,
    entity_type TEXT NOT NULL,
    entity_id TEXT,
    event_data JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 7. تفعيل حماية البيانات RLS
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customer_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.merchant_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.logistics_offices ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_events ENABLE ROW LEVEL SECURITY;

-- 8. المستخدم يرى بيانات حسابه فقط
DROP POLICY IF EXISTS profiles_select_own
ON public.profiles;

CREATE POLICY profiles_select_own
ON public.profiles
FOR SELECT
TO authenticated
USING (id = (SELECT auth.uid()));

-- 9. العميل يرى بياناته فقط
CREATE POLICY customer_select_own
ON public.customer_profiles
FOR SELECT
TO authenticated
USING (user_id = (SELECT auth.uid()));

CREATE POLICY customer_insert_own
ON public.customer_profiles
FOR INSERT
TO authenticated
WITH CHECK (user_id = (SELECT auth.uid()));

-- 10. التاجر يرى ملفه فقط
CREATE POLICY merchant_select_own
ON public.merchant_profiles
FOR SELECT
TO authenticated
USING (owner_user_id = (SELECT auth.uid()));

CREATE POLICY merchant_insert_own
ON public.merchant_profiles
FOR INSERT
TO authenticated
WITH CHECK (
    owner_user_id = (SELECT auth.uid())
    AND review_status = 'pending'
);

-- 11. مكتب اللوجستيات يرى ملفه فقط
CREATE POLICY logistics_select_own
ON public.logistics_offices
FOR SELECT
TO authenticated
USING (owner_user_id = (SELECT auth.uid()));

CREATE POLICY logistics_insert_own
ON public.logistics_offices
FOR INSERT
TO authenticated
WITH CHECK (
    owner_user_id = (SELECT auth.uid())
    AND review_status = 'pending'
);

-- 12. لا يستطيع المستخدم قراءة سجل التدقيق مباشرة
-- تتم إدارته من خلال الخادم الموثوق فقط.

COMMIT;
